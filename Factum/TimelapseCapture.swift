//
//  TimelapseCapture.swift
//  Factum
//
//  Records continuous video via AVCaptureMovieFileOutput during study
//  sessions, then speeds up the raw recording into a ~30-second
//  timelapse using AVMutableComposition at export time.
//

import AVFoundation
import UIKit
import CoreMotion
import Observation
import AudioToolbox

// MARK: - Device Orientation (accelerometer-based)

enum DeviceOrientation: String {
    case portrait = "Portrait"
    case landscapeLeft = "LandscapeLeft"    // Home button on right (device rotated left)
    case landscapeRight = "LandscapeRight"  // Home button on left (device rotated right)

    var isLandscape: Bool {
        self == .landscapeLeft || self == .landscapeRight
    }

    var icon: String {
        isLandscape ? "rectangle" : "rectangle.portrait"
    }

    /// The video output connection rotation angle for this orientation.
    /// 0° = landscape-right (native sensor), 90° = portrait, 180° = landscape-left
    var videoRotationAngle: CGFloat {
        switch self {
        case .portrait: return 90
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        }
    }

    var displayLabel: String {
        switch self {
        case .portrait: return "Portrait"
        case .landscapeLeft, .landscapeRight: return "Landscape"
        }
    }
}

// MARK: - Recording Mode

enum RecordingMode: String {
    case timelapse = "Timelapse"
    case photoTimer = "Photo Timer"
}

// MARK: - Photo Capture Delegate

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void
    
    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }
    
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        completion(image)
    }
}

// MARK: - Timer Mode

enum TimerMode: String, CaseIterable, Identifiable {
    case continuous = "Continuous"
    case pomodoro = "Pomodoro"
    case setTime = "Set Time"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .continuous: return "infinity"
        case .pomodoro: return "timer"
        case .setTime: return "clock"
        }
    }
}

// MARK: - Pomodoro State

enum PomodoroPhase: String {
    case study = "Study"
    case shortBreak = "Break"
}

// MARK: - Movie Recording Delegate

/// Handles AVCaptureMovieFileOutput delegate callbacks.
/// Must be a separate NSObject class because TimelapseCaptureManager is @MainActor
/// and the delegate methods are called on arbitrary queues.
final class MovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    var onFinished: ((URL?, Error?) -> Void)?
    
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        onFinished?(outputFileURL, error)
    }
}

// MARK: - Timelapse Capture Manager

@MainActor
@Observable
final class TimelapseCaptureManager {
    
    // MARK: Public state
    var isRecording = false
    var isPaused = false
    var elapsedSeconds = 0
    var isExporting = false
    var exportedVideoURL: URL?
    var thumbnailImage: UIImage?
    var cameraReady = false
    
    // MARK: Recording mode
    var recordingMode: RecordingMode = .timelapse
    var capturedPhoto: UIImage?
    var beforePhoto: UIImage?       // Stored separately for before/after posts
    
    // MARK: Timer mode
    var timerMode: TimerMode = .continuous
    var setTimeDurationMinutes: Int = 60
    var pomodoroStudyMinutes: Int = 25
    var pomodoroBreakMinutes: Int = 5
    var pomodoroPhase: PomodoroPhase = .study
    var pomodoroPhaseSecondsRemaining: Int = 0
    var pomodoroCompletedCycles: Int = 0
    var pomodoroMaxCycles: Int = 0  // 0 means infinite
    var isOnBreak = false
    /// Accumulated break seconds during this pomodoro session (excluded from stats).
    private(set) var totalBreakSeconds: Int = 0
    private var breakPhaseStartDate: Date?
    
    /// Study time only — excludes pomodoro break time.
    var studySeconds: Int {
        elapsedSeconds - totalBreakSeconds
    }
    
    // MARK: Subject tracking
    var currentSubject: String = "General"
    /// Accumulated subject segments from subject switches during this session.
    /// Each entry records a subject and how many seconds were spent on it.
    private(set) var subjectSegments: [(subject: String, seconds: Int)] = []
    /// Wall-clock timestamp when the current subject segment started.
    private var subjectSegmentStart: Date?
    
    // MARK: Set time countdown
    var countdownSecondsRemaining: Int = 0
    
    // MARK: Zoom
    /// The device's actual videoZoomFactor — NOT the display value.
    var currentZoomFactor: CGFloat = 1.0
    var minZoomFactor: CGFloat = 1.0
    var maxZoomFactor: CGFloat = 10.0
    var hasUltraWide: Bool = false
    /// The actual zoom factor where the wide-angle lens sits.
    /// On a triple camera this is typically 2.0 (the first switch-over point).
    /// On a single-lens camera this is 1.0.
    var wideAngleZoomFactor: CGFloat = 1.0
    /// The device's virtualDeviceSwitchOverVideoZoomFactors.
    /// On a triple camera: [2.0, 6.0] (wide-angle at 2.0, telephoto at 6.0).
    /// On a dual-wide camera: [2.0] (wide-angle at 2.0).
    /// Empty on single-lens cameras.
    var switchOverFactors: [CGFloat] = []
    /// Apple's recommended multiplier for display zoom values.
    /// Multiply this by `videoZoomFactor` to get the value Apple Camera would show.
    var displayZoomMultiplier: CGFloat = 1.0
    
    // MARK: Orientation (auto-detected via accelerometer)
    var detectedOrientation: DeviceOrientation = .portrait
    private let motionManager = CMMotionManager()

    // MARK: Configuration
    let outputFPS: Int32 = 30

    /// Output size depends on orientation.
    /// During and after recording, uses the locked recording orientation
    /// so the writer size and post metadata stay consistent.
    var isLandscape: Bool {
        (recordingOrientation ?? detectedOrientation).isLandscape
    }
    var outputSize: CGSize {
        isLandscape ? CGSize(width: 1920, height: 1080) : CGSize(width: 1080, height: 1920)
    }
    
    // MARK: Capture session
    let captureSession = AVCaptureSession()
    private var movieOutput: AVCaptureMovieFileOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private var photoCaptureDelegate: PhotoCaptureDelegate?
    private var movieRecordingDelegate: MovieRecordingDelegate?
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var currentDevice: AVCaptureDevice?
    
    // MARK: Movie recording
    private var rawVideoURL: URL?
    private var elapsedTimer: Timer?
    
    // MARK: Wall-clock timing
    /// Actual start time — used to compute elapsed time from the wall clock
    /// instead of relying on Timer tick counts, which drift over long sessions.
    private var recordingStartDate: Date?
    /// Seconds already counted before the current start (used when resuming from background)
    private var elapsedBeforeCurrentStart: Int = 0
    
    // MARK: Background support
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundDate: Date?
    
    // MARK: - Setup
    
    func setupCamera() {
        // Use .ambient so the capture session doesn't interrupt background music.
        // We only capture video (no microphone), so this is safe.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

        let session = captureSession
        
        // If the session already has inputs and a working photo output, just
        // make sure it's running — no need to re-configure.
        if !session.inputs.isEmpty, let existing = photoOutput,
           session.outputs.contains(where: { $0 === existing }) {
            let capturedSession = session
            Task.detached {
                if !capturedSession.isRunning {
                    capturedSession.startRunning()
                }
                await MainActor.run { [weak self] in
                    self?.cameraReady = true
                }
            }
            return
        }
        
        // Try ultra wide first for wide-angle support, fall back to wide
        let device = bestCamera(for: currentCameraPosition)
        guard let device else { return }
        
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        
        // Movie file output for continuous video recording
        let movie = AVCaptureMovieFileOutput()
        
        session.beginConfiguration()
        // Use .high preset for video recording — this is what Apple's AVCam
        // uses for movie capture.  .high supports multi-lens virtual cameras
        // (triple, dual-wide) with their full zoom range including ultra-wide.
        // .hd1920x1080 restricts to a single lens; .photo is optimized for
        // still capture and may not work well with AVCaptureMovieFileOutput.
        session.sessionPreset = .high
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(movie) {
            session.addOutput(movie)
        }
        
        // Add photo output for still photo capture (used in photo timer mode)
        let photo = AVCapturePhotoOutput()
        if session.canAddOutput(photo) {
            session.addOutput(photo)
        }
        photoOutput = photo
        
        session.commitConfiguration()
        
        movieOutput = movie
        currentDevice = device
        configureConnectionOrientation()
        updateZoomLimits()
        
        print("[CAMERA] Device: \(device.localizedName), type: \(device.deviceType)")
        print("[CAMERA] Zoom range: \(device.minAvailableVideoZoomFactor)x – \(device.maxAvailableVideoZoomFactor)x")
        print("[CAMERA] hasUltraWide: \(hasUltraWide), minZoom: \(minZoomFactor)")
        
        // Start running on a background queue to avoid blocking the main thread
        let capturedSession = session
        Task.detached {
            capturedSession.startRunning()
            await MainActor.run { [weak self] in
                guard let self else { return }
                // Re-query zoom limits now that the session is running —
                // multi-lens devices may report switch-over factors only after start.
                self.updateZoomLimits()
                // Start at wide-angle (Apple Camera default) — this is factor 2.0
                // on triple camera, 1.0 on single lens.
                self.setZoom(self.wideAngleZoomFactor)
                self.cameraReady = true
            }
        }
    }
    
    /// Configure the movie output connection rotation based on detected orientation.
    /// The preview layer is independent (always portrait), so changing this
    /// only affects the recorded video — not what the user sees.
    private func configureConnectionOrientation() {
        guard let output = movieOutput,
              let connection = output.connection(with: .video) else { return }
        let angle = detectedOrientation.videoRotationAngle
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        // Mirror front camera so it matches the preview
        connection.isVideoMirrored = (currentCameraPosition == .front)
    }

    /// Start accelerometer-based orientation detection.
    /// Updates `detectedOrientation` and reconfigures the capture connection.
    func startOrientationDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.3
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let x = data.acceleration.x
            let y = data.acceleration.y

            // Determine orientation from gravity vector.
            // Require a threshold to avoid flipping on small tilts.
            let threshold = 0.55
            let newOrientation: DeviceOrientation
            if abs(x) > abs(y) {
                // Landscape — iOS accelerometer: positive x = tilted right (home button on right)
                if x > threshold {
                    newOrientation = .landscapeLeft   // Home button on right
                } else if x < -threshold {
                    newOrientation = .landscapeRight  // Home button on left
                } else {
                    return // In the dead zone, keep current
                }
            } else {
                // Portrait or upside-down
                if y < -threshold {
                    newOrientation = .portrait
                } else {
                    return // Upside-down or flat — ignore, keep current
                }
            }

            if newOrientation != self.detectedOrientation {
                // During recording, both orientation and connection are locked
                // so the output stays in sync.
                guard !self.isRecording else { return }
                self.detectedOrientation = newOrientation
                self.configureConnectionOrientation()
            }
        }
    }

    /// Stop accelerometer updates.
    func stopOrientationDetection() {
        motionManager.stopAccelerometerUpdates()
    }
    
    private func bestCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Use DiscoverySession to find the best multi-lens virtual camera.
        // Order matters: triple > dual-wide > dual > wide-angle.
        // The discovery session returns devices in the order you request,
        // so the first match is the best device.
        let preferredTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferredTypes,
            mediaType: .video,
            position: position
        )
        let device = discovery.devices.first
        if let device {
            print("[CAMERA] DiscoverySession picked: \(device.localizedName), type: \(device.deviceType)")
            print("[CAMERA] Available devices: \(discovery.devices.map { "\($0.localizedName) (\($0.deviceType))" })")
        }
        return device
    }
    
    func requestPermissionAndSetup() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            setupCamera()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { setupCamera() }
        default:
            break
        }
    }
    
    // MARK: - Camera Controls
    
    func flipCamera() {
        let newPosition: AVCaptureDevice.Position = currentCameraPosition == .front ? .back : .front
        print("[FLIP] Flipping from \(currentCameraPosition == .front ? "front" : "back") to \(newPosition == .front ? "front" : "back")")
        
        guard let newDevice = bestCamera(for: newPosition) else {
            print("[FLIP] ERROR: bestCamera returned nil for \(newPosition == .front ? "front" : "back")")
            return
        }
        
        guard let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
            print("[FLIP] ERROR: Could not create input for \(newDevice.localizedName)")
            return
        }
        
        captureSession.beginConfiguration()
        
        // Remove all existing inputs and outputs
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        
        // Add new input
        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
        } else {
            print("[FLIP] ERROR: canAddInput returned false")
        }
        
        // Create fresh outputs
        let newMovie = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(newMovie) {
            captureSession.addOutput(newMovie)
        } else {
            print("[FLIP] ERROR: canAddOutput(movie) returned false")
        }
        movieOutput = newMovie
        
        let newPhoto = AVCapturePhotoOutput()
        if captureSession.canAddOutput(newPhoto) {
            captureSession.addOutput(newPhoto)
        } else {
            print("[FLIP] ERROR: canAddOutput(photo) returned false")
        }
        photoOutput = newPhoto
        
        captureSession.commitConfiguration()
        currentCameraPosition = newPosition
        currentDevice = newDevice
        configureConnectionOrientation()
        updateZoomLimits()
        setZoom(wideAngleZoomFactor)
        
        print("[FLIP] Success — now on \(newPosition == .front ? "front" : "back"), device: \(newDevice.localizedName)")
    }
    
    private func updateZoomLimits() {
        guard let device = currentDevice else { return }
        minZoomFactor = device.minAvailableVideoZoomFactor
        maxZoomFactor = min(device.maxAvailableVideoZoomFactor, 15.0)
        currentZoomFactor = device.videoZoomFactor
        
        // On virtual multi-lens devices (triple, dual-wide), the zoom factor
        // range starts at 1.0 (ultra-wide) and the wide-angle lens is at the
        // first switch-over point (typically 2.0).  Apple's Camera app shows
        // the wide-angle as "1×" and the ultra-wide as "0.5×" by dividing the
        // actual zoom factor by the wide-angle switch-over point.
        //
        // virtualDeviceSwitchOverVideoZoomFactors tells us where each lens
        // transition happens.  On a triple camera: [2.0, 6.0] means
        //   ultra-wide (1.0) → wide (2.0) → telephoto (6.0)
        switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
        let isMultiLens = device.deviceType == .builtInTripleCamera
            || device.deviceType == .builtInDualWideCamera
        
        if isMultiLens && currentCameraPosition == .back, let firstSwitch = switchOverFactors.first {
            wideAngleZoomFactor = firstSwitch
            hasUltraWide = true
        } else {
            wideAngleZoomFactor = 1.0
            hasUltraWide = false
        }
        
        // Apple's official multiplier for converting videoZoomFactor → display value
        displayZoomMultiplier = device.displayVideoZoomFactorMultiplier
        
        print("[ZOOM] min=\(minZoomFactor), max=\(maxZoomFactor), wideAngle=\(wideAngleZoomFactor), hasUltraWide=\(hasUltraWide), switchOvers=\(switchOverFactors), displayMultiplier=\(displayZoomMultiplier), deviceType=\(device.deviceType)")
    }
    
    /// Set the device zoom using the actual AVFoundation zoom factor (not display value).
    func setZoom(_ factor: CGFloat, animated: Bool = false) {
        guard let device = currentDevice else { return }
        let clamped = max(device.minAvailableVideoZoomFactor,
                         min(factor, min(device.maxAvailableVideoZoomFactor, 15.0)))
        do {
            try device.lockForConfiguration()
            if animated {
                device.ramp(toVideoZoomFactor: clamped, withRate: 8.0)
            } else {
                device.videoZoomFactor = clamped
            }
            device.unlockForConfiguration()
            currentZoomFactor = clamped
        } catch {}
    }
    
    // MARK: - Recording
    
    /// The orientation captured at recording start.  Persists after recording
    /// stops so that `isLandscape` / `outputSize` remain correct during export
    /// and when passing metadata to PostCaptionView.  Cleared on `cleanup()`.
    private(set) var recordingOrientation: DeviceOrientation?

    func startRecording() {
        elapsedSeconds = 0
        isRecording = true
        exportedVideoURL = nil
        thumbnailImage = nil
        isOnBreak = false
        totalBreakSeconds = 0
        breakPhaseStartDate = nil
        pomodoroCompletedCycles = 0
        pomodoroPhase = .study
        recordingStartDate = Date()
        elapsedBeforeCurrentStart = 0
        beginSubjectSegment()
        
        // Lock the current orientation for the entire recording session.
        recordingOrientation = detectedOrientation
        configureConnectionOrientation()
        
        // Set up timer-specific state
        switch timerMode {
        case .continuous:
            break
        case .pomodoro:
            pomodoroPhaseSecondsRemaining = pomodoroStudyMinutes * 60
            pomodoroPhase = .study
        case .setTime:
            countdownSecondsRemaining = setTimeDurationMinutes * 60
        }
        
        // Start continuous video recording
        guard let movieOutput else { return }
        
        let sessionID = UUID().uuidString
        let docsDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let rawURL = docsDir.appendingPathComponent("factum_raw_\(sessionID).mov")
        rawVideoURL = rawURL
        
        let delegate = MovieRecordingDelegate()
        delegate.onFinished = { [weak self] url, error in
            if let error {
                print("[CAPTURE] Movie recording finished with error: \(error.localizedDescription)")
            }
            Task { @MainActor [weak self] in
                self?.rawVideoURL = url
            }
        }
        movieRecordingDelegate = delegate
        movieOutput.startRecording(to: rawURL, recordingDelegate: delegate)
        
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
    
    // MARK: - Photo Timer Mode
    
    /// Capture a single still photo using the photo output.
    func capturePhoto() async -> UIImage? {
        guard let photoOutput else { return nil }
        
        return await withCheckedContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            let delegate = PhotoCaptureDelegate { image in
                continuation.resume(returning: image)
            }
            self.photoCaptureDelegate = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
    
    /// Start the timer without recording video frames.
    /// Used in photo timer mode — the timer ticks identically to timelapse mode
    /// but no video is recorded.
    func startTimerOnly() {
        elapsedSeconds = 0
        isRecording = true
        exportedVideoURL = nil
        thumbnailImage = nil
        isOnBreak = false
        totalBreakSeconds = 0
        breakPhaseStartDate = nil
        pomodoroCompletedCycles = 0
        pomodoroPhase = .study
        recordingStartDate = Date()
        elapsedBeforeCurrentStart = 0
        beginSubjectSegment()
        
        // Lock orientation
        recordingOrientation = detectedOrientation
        
        // Set up timer-specific state
        switch timerMode {
        case .continuous:
            break
        case .pomodoro:
            pomodoroPhaseSecondsRemaining = pomodoroStudyMinutes * 60
            pomodoroPhase = .study
        case .setTime:
            countdownSecondsRemaining = setTimeDurationMinutes * 60
        }
        
        // No video recording — just the tick timer
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        
        // Stop the camera session to save battery (no preview needed during timer)
        let session = captureSession
        Task.detached { session.stopRunning() }
    }
    
    private func tick() {
        guard !isPaused else { return }
        
        // Compute elapsed time from wall clock instead of counting ticks.
        // Timer fires can drift by tens of seconds over multi-hour sessions.
        if let start = recordingStartDate {
            elapsedSeconds = elapsedBeforeCurrentStart + Int(Date().timeIntervalSince(start))
        } else {
            elapsedSeconds += 1
        }
        
        switch timerMode {
        case .continuous:
            break
            
        case .pomodoro:
            pomodoroPhaseSecondsRemaining -= 1
            if pomodoroPhaseSecondsRemaining <= 0 {
                playAlertSound()
                if pomodoroPhase == .study {
                    pomodoroCompletedCycles += 1
                    // Check if max cycles reached
                    if pomodoroMaxCycles > 0 && pomodoroCompletedCycles >= pomodoroMaxCycles {
                        stopRecording()
                        return
                    }
                    pomodoroPhase = .shortBreak
                    pomodoroPhaseSecondsRemaining = pomodoroBreakMinutes * 60
                    isOnBreak = true
                    breakPhaseStartDate = Date()
                } else {
                    pomodoroPhase = .study
                    pomodoroPhaseSecondsRemaining = pomodoroStudyMinutes * 60
                    isOnBreak = false
                    // Accumulate the break that just ended
                    if let breakStart = breakPhaseStartDate {
                        totalBreakSeconds += Int(Date().timeIntervalSince(breakStart))
                    }
                    breakPhaseStartDate = nil
                }
            }
            
        case .setTime:
            countdownSecondsRemaining -= 1
            if countdownSecondsRemaining <= 0 {
                playAlertSound()
                stopRecording()
            }
        }
    }
    
    func stopRecording() {
        // Snapshot elapsed time so it survives a subsequent resume (e.g. the
        // user taps Back on the post screen).
        if let start = recordingStartDate {
            elapsedBeforeCurrentStart += Int(Date().timeIntervalSince(start))
            elapsedSeconds = elapsedBeforeCurrentStart
        }
        recordingStartDate = nil
        
        // Finalize any in-progress break so studySeconds is accurate
        if let breakStart = breakPhaseStartDate {
            totalBreakSeconds += Int(Date().timeIntervalSince(breakStart))
            breakPhaseStartDate = nil
        }
        
        isRecording = false
        isPaused = false
        
        // Stop continuous video recording
        if let movieOutput, movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        
        // Re-sync the connection to the current physical orientation
        configureConnectionOrientation()
    }
    
    // MARK: - Subject Tracking
    
    /// Begin tracking the first subject segment. Called when recording/timer starts.
    private func beginSubjectSegment() {
        subjectSegments = []
        subjectSegmentStart = Date()
    }
    
    /// Finalize the current subject segment, recording how long it lasted.
    private func finalizeCurrentSegment() {
        guard let start = subjectSegmentStart else { return }
        let seconds = max(1, Int(Date().timeIntervalSince(start)))
        // Merge into existing entry for the same subject, or append new
        if let idx = subjectSegments.firstIndex(where: { $0.subject == currentSubject }) {
            subjectSegments[idx].seconds += seconds
        } else {
            subjectSegments.append((subject: currentSubject, seconds: seconds))
        }
        subjectSegmentStart = nil
    }
    
    /// Switch to a different subject mid-session. Finalizes the current segment
    /// and starts a new one for the new subject.
    func switchSubject(to newSubject: String) {
        guard newSubject != currentSubject else { return }
        finalizeCurrentSegment()
        currentSubject = newSubject
        subjectSegmentStart = Date()
    }
    
    /// Returns the finalized subject segments for the completed session.
    /// Merges any in-progress segment and sorts by time descending.
    func finalizedSegments() -> [SubjectSegment] {
        // Finalize any in-progress segment
        finalizeCurrentSegment()
        return subjectSegments
            .map { SubjectSegment(subject: $0.subject, seconds: $0.seconds) }
            .sorted { $0.seconds > $1.seconds }
    }
    
    // MARK: - Pause / Resume
    
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        
        // Snapshot elapsed time and stop the tick timer
        if let start = recordingStartDate {
            elapsedBeforeCurrentStart += Int(Date().timeIntervalSince(start))
        }
        recordingStartDate = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        
        // Snapshot current subject segment time
        finalizeCurrentSegment()
        
        // Pause the movie file output (native support)
        if let movieOutput, movieOutput.isRecording {
            movieOutput.pauseRecording()
        }
    }
    
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        
        // Resume wall-clock tracking from now
        recordingStartDate = Date()
        subjectSegmentStart = Date()
        
        // Resume the movie file output (native support)
        if let movieOutput, movieOutput.isRecordingPaused {
            movieOutput.resumeRecording()
        }
        
        // Restart the tick timer (invalidate any stale timer first)
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
    
    // MARK: - Sound
    
    func playAlertSound() {
        AudioServicesPlaySystemSound(1005) // System "alarm" sound
        // Also vibrate
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    
    // MARK: - Export timelapse
    
    /// Speeds up the raw continuous recording into a ~30-second timelapse
    /// using AVMutableComposition.  Safe to call multiple times.
    func exportTimelapse() async -> URL? {
        if let existing = exportedVideoURL {
            return existing
        }
        guard !isExporting else { return nil }
        guard let rawURL = rawVideoURL,
              FileManager.default.fileExists(atPath: rawURL.path) else { return nil }

        isExporting = true

        let asset = AVURLAsset(url: rawURL)
        
        // Load duration and video track
        guard let duration = try? await asset.load(.duration),
              duration.seconds > 0 else {
            isExporting = false
            return nil
        }
        
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            isExporting = false
            return nil
        }
        
        // Generate thumbnail from first frame before speed-up
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1920)
        if let cgImage = try? await generator.image(at: .zero).image {
            thumbnailImage = UIImage(cgImage: cgImage)
        }
        
        // Target output: 30 seconds at 30fps
        let targetSeconds: Double = 30.0
        let targetDuration = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        
        // Create composition with sped-up track
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            isExporting = false
            return nil
        }
        
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        do {
            try compositionTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        } catch {
            print("[EXPORT] Failed to insert time range: \(error.localizedDescription)")
            isExporting = false
            return nil
        }
        
        // Preserve the source video's orientation transform so portrait
        // recordings are exported upright instead of sideways.
        if let transform = try? await videoTrack.load(.preferredTransform) {
            compositionTrack.preferredTransform = transform
        }
        
        // Scale time to target duration (this creates the timelapse effect)
        compositionTrack.scaleTimeRange(timeRange, toDuration: targetDuration)
        
        // Export
        let outputURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("factum_\(UUID().uuidString).mp4")
        
        guard let exportSession = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else {
            isExporting = false
            return nil
        }
        
        do {
            try await exportSession.export(to: outputURL, as: .mp4)
        } catch {
            print("[EXPORT] Export failed: \(error.localizedDescription)")
            // Clean up raw recording even on failure
            try? FileManager.default.removeItem(at: rawURL)
            rawVideoURL = nil
            isExporting = false
            return nil
        }
        
        // Clean up raw recording to free disk space
        try? FileManager.default.removeItem(at: rawURL)
        rawVideoURL = nil
        
        isExporting = false
        exportedVideoURL = outputURL
        return outputURL
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        stopRecording()
        recordingOrientation = nil
        recordingStartDate = nil
        elapsedBeforeCurrentStart = 0
        capturedPhoto = nil
        beforePhoto = nil
        subjectSegments = []
        subjectSegmentStart = nil
        stopOrientationDetection()
        endBackgroundTask()
        // Clean up any raw recording file
        if let rawURL = rawVideoURL {
            try? FileManager.default.removeItem(at: rawURL)
            rawVideoURL = nil
        }
        captureSession.stopRunning()
    }
    
    // MARK: - Background Support
    
    /// Called when the app is about to enter the background
    func handleEnterBackground() {
        guard isRecording else { return }
        
        // Snapshot the current elapsed time and clear the start date.
        // When we return to foreground we'll set a new start date and
        // resume from the snapshotted value.
        backgroundDate = Date()
        if let start = recordingStartDate {
            elapsedBeforeCurrentStart = elapsedBeforeCurrentStart + Int(Date().timeIntervalSince(start))
        }
        recordingStartDate = nil
        
        // Stop timers — they won't fire in the background anyway
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        
        // Pause movie recording when entering background — the system will
        // interrupt the capture session anyway, and pausing ensures we get
        // a clean file without gaps or corruption.
        if let movieOutput, movieOutput.isRecording, !movieOutput.isRecordingPaused {
            movieOutput.pauseRecording()
        }
        
        // Request background time to keep the session alive as long as possible
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            // System is about to kill our background time — end gracefully
            Task { @MainActor in
                self?.endBackgroundTask()
            }
        }
    }
    
    /// Called when the app returns to the foreground
    func handleEnterForeground() {
        guard isRecording, let bgDate = backgroundDate else { return }
        
        // Calculate how many seconds passed while backgrounded
        let secondsInBackground = Int(Date().timeIntervalSince(bgDate))
        backgroundDate = nil
        
        // Resume wall-clock tracking from now, carrying forward the
        // previously accumulated elapsed time plus background time.
        elapsedBeforeCurrentStart += secondsInBackground
        recordingStartDate = Date()
        elapsedSeconds = elapsedBeforeCurrentStart
        
        // Resume movie recording if it was paused for background
        if let movieOutput, movieOutput.isRecordingPaused {
            movieOutput.resumeRecording()
        }
        
        // Update timer-specific countdowns
        switch timerMode {
        case .continuous:
            break
        case .pomodoro:
            // Fast-forward through pomodoro phases, tracking break time
            // Finalize any in-progress break before fast-forwarding
            if let breakStart = breakPhaseStartDate {
                totalBreakSeconds += Int(bgDate.timeIntervalSince(breakStart))
                breakPhaseStartDate = nil
            }
            var remaining = secondsInBackground
            while remaining > 0 {
                if pomodoroPhaseSecondsRemaining <= remaining {
                    let phaseTime = pomodoroPhaseSecondsRemaining
                    remaining -= phaseTime
                    if pomodoroPhase == .study {
                        pomodoroCompletedCycles += 1
                        if pomodoroMaxCycles > 0 && pomodoroCompletedCycles >= pomodoroMaxCycles {
                            stopRecording()
                            return
                        }
                        pomodoroPhase = .shortBreak
                        pomodoroPhaseSecondsRemaining = pomodoroBreakMinutes * 60
                        isOnBreak = true
                    } else {
                        // A full break phase just completed — count it
                        totalBreakSeconds += phaseTime
                        pomodoroPhase = .study
                        pomodoroPhaseSecondsRemaining = pomodoroStudyMinutes * 60
                        isOnBreak = false
                    }
                } else {
                    // Partial phase — if we're in a break, track the partial break time
                    if pomodoroPhase == .shortBreak {
                        totalBreakSeconds += remaining
                        breakPhaseStartDate = Date()
                    }
                    pomodoroPhaseSecondsRemaining -= remaining
                    remaining = 0
                }
            }
        case .setTime:
            countdownSecondsRemaining -= secondsInBackground
            if countdownSecondsRemaining <= 0 {
                countdownSecondsRemaining = 0
                playAlertSound()
                stopRecording()
                return
            }
        }
        
        // Restart elapsed timer
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        
        // Restart the capture session if it was interrupted — but only for
        // timelapse mode where video capture is active.  In photo timer mode
        // the session was deliberately stopped to save battery.
        if recordingMode == .timelapse && !captureSession.isRunning {
            let session = captureSession
            Task.detached {
                session.startRunning()
            }
        }
        
        endBackgroundTask()
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
}
