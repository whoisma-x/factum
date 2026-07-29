//
//  TimelapseCapture.swift
//  Factum
//
//  Captures frames from the camera and writes them directly to an
//  AVAssetWriter during recording.  Frames are captured at the full
//  camera rate and adaptively sub-sampled so the final video is a
//  smooth ~20-25 second timelapse regardless of recording length.
//  No frames are ever accumulated in memory.
//

import AVFoundation
import UIKit
import CoreImage
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

// MARK: - Thread-safe latest frame holder (for preview only)

final class LatestFrameHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _frame: CGImage?
    
    var frame: CGImage? {
        get { lock.lock(); defer { lock.unlock() }; return _frame }
        set { lock.lock(); _frame = newValue; lock.unlock() }
    }
}

// MARK: - Timelapse Writer — uniform-speed, bounded-storage frame collector

/// Collects JPEG-compressed frames on disk during recording, keeping at
/// most `maxFrames` (900 = 30s × 30fps).  When the buffer fills up, every
/// other frame is deleted so the remaining frames are still evenly spaced
/// and the skip interval is doubled.  At export time the stored frames are
/// assembled into a 30-second H.264 video.
///
/// Storage is bounded to ~maxFrames × ~50KB ≈ 45 MB regardless of recording
/// duration — safe for 24+ hour sessions.
final class TimelapseWriter: @unchecked Sendable {
    private let lock = NSLock()

    let outputSize: CGSize
    let outputFPS: Int32
    let maxFrames: Int  // 30s × 30fps = 900

    /// Directory holding numbered JPEG frame files
    private var frameDir: URL?
    /// Ordered list of frame file URLs currently kept
    private var frameFiles: [URL] = []
    private var totalCameraFrames: Int = 0
    private var isFinished: Bool = false

    /// How many camera frames to skip between captures.
    /// Starts at 3 (~10fps from 30fps camera).  Doubles each time we thin.
    private var skipInterval: Int = 3
    private var framesSinceLastWrite: Int = 0
    private var frameCounter: Int = 0  // monotonic counter for unique file names
    private var consecutiveWriteFailures: Int = 0

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    private(set) var firstFrameImage: CGImage?

    init(outputSize: CGSize, outputFPS: Int32, maxFrames: Int = 900) {
        self.outputSize = outputSize
        self.outputFPS = outputFPS
        self.maxFrames = maxFrames
    }

    /// Remove any orphaned frame directories left over from a previous session
    /// that crashed or was force-quit before cleanup could run.
    static func cleanupOrphanedFrameDirs() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: caches, includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("factum_frames_") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Prepare a temp directory for frame storage.
    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Clean up any orphaned frame dirs from previous sessions
        Self.cleanupOrphanedFrameDirs()

        // Use cachesDirectory instead of temporaryDirectory — iOS can purge
        // temp files while the app is backgrounded during long study sessions,
        // which would silently destroy recorded frames.  Caches are only purged
        // under extreme disk pressure and never while the app is in foreground.
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("factum_frames_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        frameDir = dir
        frameFiles = []
        totalCameraFrames = 0
        isFinished = false
        skipInterval = 3
        framesSinceLastWrite = 0
        frameCounter = 0
        consecutiveWriteFailures = 0
        firstFrameImage = nil

        return true
    }

    /// Feed a camera sample buffer.  Called on the capture queue.
    func appendFrame(sampleBuffer: CMSampleBuffer) {
        lock.lock()
        guard !isFinished, let frameDir else {
            lock.unlock()
            return
        }
        // If disk writes keep failing (e.g. disk full), stop trying to prevent
        // CPU waste on frames that will never be saved.
        guard consecutiveWriteFailures < 10 else {
            lock.unlock()
            return
        }
        // Check available disk space periodically (every ~30 frames) to avoid
        // writing until the disk is completely full.  50 MB headroom keeps the
        // OS and other apps from suffering.
        if frameCounter % 30 == 0 {
            let avail = (try? URL(fileURLWithPath: NSHomeDirectory())
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage) ?? 0
            if avail < 50_000_000 { // 50 MB
                lock.unlock()
                return
            }
        }

        totalCameraFrames += 1
        framesSinceLastWrite += 1

        guard framesSinceLastWrite >= skipInterval else {
            lock.unlock()
            return
        }
        framesSinceLastWrite = 0

        let currentIndex = frameCounter
        frameCounter += 1
        let shouldSaveThumb = (firstFrameImage == nil)
        lock.unlock()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Autoreleasepool prevents CIImage/CGImage/UIImage transients from
        // accumulating over hours of continuous recording.
        autoreleasepool {
            // Render to the correct output size
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let srcW = ciImage.extent.width
            let srcH = ciImage.extent.height
            let outW = outputSize.width
            let outH = outputSize.height

            let finalImage: CIImage
            if Int(srcW) != Int(outW) || Int(srcH) != Int(outH) {
                let scale = max(outW / srcW, outH / srcH)
                let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let cropX = (scaled.extent.width - outW) / 2
                let cropY = (scaled.extent.height - outH) / 2
                finalImage = scaled.cropped(to: CGRect(
                    x: scaled.extent.origin.x + cropX,
                    y: scaled.extent.origin.y + cropY,
                    width: outW, height: outH
                ))
            } else {
                finalImage = ciImage
            }

            // Save thumbnail from first frame
            if shouldSaveThumb {
                if let cg = ciContext.createCGImage(finalImage, from: finalImage.extent) {
                    lock.lock()
                    firstFrameImage = cg
                    lock.unlock()
                }
            }

            // Write JPEG to disk
            let fileURL = frameDir.appendingPathComponent(String(format: "%08d.jpg", currentIndex))
            if let cg = ciContext.createCGImage(finalImage, from: finalImage.extent) {
                let uiImage = UIImage(cgImage: cg)
                if let data = uiImage.jpegData(compressionQuality: 0.8) {
                    do {
                        try data.write(to: fileURL, options: .atomic)

                        lock.lock()
                        frameFiles.append(fileURL)
                        consecutiveWriteFailures = 0

                        // If we've exceeded the budget, thin by removing every other frame
                        if frameFiles.count > maxFrames {
                            thinFrames()
                        }
                        lock.unlock()
                    } catch {
                        // Disk full or other I/O error — track so we can stop
                        // wasting CPU if writes are consistently failing.
                        lock.lock()
                        consecutiveWriteFailures += 1
                        lock.unlock()
                    }
                }
            }
        }
    }

    /// Remove every other frame file to halve the count, then double skipInterval.
    /// After thinning, frames remain evenly spaced in time.
    private func thinFrames() {
        // Keep frames at even indices, delete odd indices
        var kept: [URL] = []
        for (i, url) in frameFiles.enumerated() {
            if i % 2 == 0 {
                kept.append(url)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        frameFiles = kept
        skipInterval *= 2
    }

    /// Build a 30-second video from the collected frames.
    func finish() async -> URL? {
        lock.lock()
        guard !frameFiles.isEmpty else {
            cleanup()
            lock.unlock()
            return nil
        }
        isFinished = true
        // Filter out any frame files that were deleted by the OS (e.g. cache
        // cleanup during a long background session) or corrupted by a partial
        // write.  Without this, finish() silently skips missing frames and can
        // produce a very short or empty video.
        let frames = frameFiles.filter { FileManager.default.fileExists(atPath: $0.path) }
        lock.unlock()
        
        guard !frames.isEmpty else {
            cleanupFrameDir()
            return nil
        }

        let outputURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("factum_\(UUID().uuidString).mp4")

        guard let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            cleanupFrameDir()
            return nil
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
            ]
        )

        assetWriter.add(input)
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)

        // Reuse a single pixel buffer for all frames to avoid memory spikes.
        // Each 1920×1080 BGRA buffer is ~8MB — allocating 900 would be 7+ GB.
        let bufferAttrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        var reusableBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            nil,
            Int(outputSize.width), Int(outputSize.height),
            kCVPixelFormatType_32BGRA,
            bufferAttrs as CFDictionary,
            &reusableBuffer
        )
        guard let pixelBuffer = reusableBuffer else {
            cleanupFrameDir()
            return nil
        }

        // Write each frame at evenly-spaced timestamps
        var consecutiveAppendFailures = 0
        for (index, frameURL) in frames.enumerated() {
            // Wait for writer to be ready with exponential backoff
            var waitMs: UInt64 = 5
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(waitMs))
                waitMs = min(waitMs * 2, 100)
                if assetWriter.status == .failed { break }
            }
            
            // Bail if the writer has entered an error state
            if assetWriter.status == .failed { break }

            // Autoreleasepool prevents transient Data/UIImage/CGImage from
            // accumulating across 900 iterations — critical for long sessions.
            let appended: Bool = autoreleasepool {
                guard let imageData = try? Data(contentsOf: frameURL),
                      let uiImage = UIImage(data: imageData),
                      let cgImage = uiImage.cgImage else { return false }

                let time = CMTime(value: Int64(index), timescale: outputFPS)

                CVPixelBufferLockBaseAddress(pixelBuffer, [])
                let ciImg = CIImage(cgImage: cgImage)
                ciContext.render(ciImg, to: pixelBuffer, bounds: CGRect(origin: .zero, size: outputSize), colorSpace: colorSpace)
                CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

                return adaptor.append(pixelBuffer, withPresentationTime: time)
            }
            if appended {
                consecutiveAppendFailures = 0
            } else {
                consecutiveAppendFailures += 1
                // If many frames in a row fail to append, the writer is likely
                // in a bad state — bail out instead of looping through 900 no-ops.
                if consecutiveAppendFailures >= 20 { break }
            }
        }

        input.markAsFinished()
        await assetWriter.finishWriting()

        cleanupFrameDir()

        guard assetWriter.status == .completed else { return nil }
        return outputURL
    }

    /// Called when the system sends a memory warning.  Thin the frame
    /// buffer by half and double the skip interval — same as hitting the
    /// max, but triggered earlier by OS pressure.
    func thinOnMemoryPressure() {
        lock.lock()
        guard frameFiles.count > 10 else {
            lock.unlock()
            return
        }
        thinFrames()
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cleanup()
        lock.unlock()
    }

    private func cleanup() {
        cleanupFrameDir()
        frameFiles = []
    }

    private func cleanupFrameDir() {
        if let dir = frameDir {
            try? FileManager.default.removeItem(at: dir)
        }
    }
}

// MARK: - Capture Delegate — feeds frames to both preview holder and timelapse writer

final class CaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let frameHolder: LatestFrameHolder
    var timelapseWriter: TimelapseWriter?
    var isRecording: Bool = false
    var isOnBreak: Bool = false
    private let ciContext = CIContext()
    private var previewSkipCount: Int = 0
    
    init(frameHolder: LatestFrameHolder) {
        self.frameHolder = frameHolder
    }
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Update preview at ~10fps instead of every frame to reduce CPU load
        previewSkipCount += 1
        if previewSkipCount >= 3 {
            previewSkipCount = 0
            autoreleasepool {
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                        frameHolder.frame = cgImage
                    }
                }
            }
        }
        
        // Write to timelapse if recording and not on break
        if isRecording && !isOnBreak {
            timelapseWriter?.appendFrame(sampleBuffer: sampleBuffer)
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
    var currentZoomFactor: CGFloat = 1.0
    var minZoomFactor: CGFloat = 1.0
    var maxZoomFactor: CGFloat = 10.0
    var hasUltraWide: Bool = false
    
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
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private var photoCaptureDelegate: PhotoCaptureDelegate?
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var currentDevice: AVCaptureDevice?
    
    // MARK: Frame capture — writes directly to disk via TimelapseWriter
    private var timelapseWriter: TimelapseWriter?
    private var elapsedTimer: Timer?
    
    // MARK: Thread-safe frame
    private let frameHolder = LatestFrameHolder()
    private var captureDelegate: CaptureDelegate?
    private let captureQueue = DispatchQueue(label: "com.factum.capture", qos: .userInitiated)
    
    // MARK: Wall-clock timing
    /// Actual start time — used to compute elapsed time from the wall clock
    /// instead of relying on Timer tick counts, which drift over long sessions.
    private var recordingStartDate: Date?
    /// Seconds already counted before the current start (used when resuming from background)
    private var elapsedBeforeCurrentStart: Int = 0
    
    // MARK: Background support
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundDate: Date?
    private var memoryWarningObserver: NSObjectProtocol?
    
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
        
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let delegate = CaptureDelegate(frameHolder: frameHolder)
        output.setSampleBufferDelegate(delegate, queue: captureQueue)
        captureDelegate = delegate
        
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        // Add photo output for still photo capture (used in photo timer mode)
        let photo = AVCapturePhotoOutput()
        if session.canAddOutput(photo) {
            session.addOutput(photo)
        }
        photoOutput = photo
        
        session.commitConfiguration()
        
        videoOutput = output
        currentDevice = device
        configureConnectionOrientation()
        updateZoomLimits()
        
        // Start running on a background queue to avoid blocking the main thread
        let capturedSession = session
        Task.detached {
            capturedSession.startRunning()
            await MainActor.run { [weak self] in
                self?.cameraReady = true
            }
        }
    }
    
    /// Configure the video output connection rotation based on detected orientation.
    /// The preview layer is independent (always portrait), so changing this
    /// only affects the captured frames — not what the user sees.
    private func configureConnectionOrientation() {
        guard let output = videoOutput,
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
                // so the writer's output size stays in sync with the frames.
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
        // Use the triple/dual camera if available — it provides seamless zoom
        // across ultra-wide, wide, and telephoto lenses
        if let tripleCamera = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position) {
            return tripleCamera
        }
        if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position) {
            return dualWide
        }
        if let dualCamera = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position) {
            return dualCamera
        }
        // Fall back to standard wide-angle camera
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
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
        guard let newDevice = bestCamera(for: newPosition) else { return }
        guard let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
        
        captureSession.beginConfiguration()
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
        }
        captureSession.commitConfiguration()
        currentCameraPosition = newPosition
        currentDevice = newDevice
        configureConnectionOrientation()
        updateZoomLimits()
        // Reset zoom when flipping
        setZoom(1.0)
    }
    
    private func updateZoomLimits() {
        guard let device = currentDevice else { return }
        minZoomFactor = device.minAvailableVideoZoomFactor
        maxZoomFactor = min(device.maxAvailableVideoZoomFactor, 15.0)
        currentZoomFactor = device.videoZoomFactor
        // Multi-lens cameras (triple, dual-wide) have a sub-1.0 min zoom for ultra-wide
        hasUltraWide = (currentCameraPosition == .back && minZoomFactor < 1.0)
    }
    
    func setZoom(_ factor: CGFloat, animated: Bool = false) {
        guard let device = currentDevice else { return }
        let clamped = max(minZoomFactor, min(factor, maxZoomFactor))
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
        // This ensures the capture connection angle and the writer's output
        // size stay in sync — changing either mid-recording would produce
        // mismatched frames.
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
        
        // Create and start the timelapse writer — frames go directly to disk
        let writer = TimelapseWriter(
            outputSize: outputSize,
            outputFPS: outputFPS
        )
        if writer.start() {
            timelapseWriter = writer
            captureDelegate?.timelapseWriter = writer
            captureDelegate?.isRecording = true
            captureDelegate?.isOnBreak = false
        }
        
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        
        // Listen for memory warnings — thin frames aggressively to avoid crash
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
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
    /// but no TimelapseWriter is created and no frames are captured.
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
        
        // No TimelapseWriter, no frame capture — just the tick timer
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        
        // Stop the camera session to save battery (no preview needed during timer)
        let session = captureSession
        Task.detached { session.stopRunning() }
    }
    
    private func handleMemoryWarning() {
        // Force the writer to thin its frame buffer immediately
        // This frees up disk-backed data and reduces bookkeeping memory
        guard let writer = timelapseWriter else { return }
        writer.thinOnMemoryPressure()
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
                    captureDelegate?.isOnBreak = true
                } else {
                    pomodoroPhase = .study
                    pomodoroPhaseSecondsRemaining = pomodoroStudyMinutes * 60
                    isOnBreak = false
                    // Accumulate the break that just ended
                    if let breakStart = breakPhaseStartDate {
                        totalBreakSeconds += Int(Date().timeIntervalSince(breakStart))
                    }
                    breakPhaseStartDate = nil
                    captureDelegate?.isOnBreak = false
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
        // user taps Back on the post screen).  Without this, resumeRecording()
        // would start from elapsedBeforeCurrentStart = 0 and reset the clock.
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
        // Note: recordingOrientation is NOT cleared here — it must persist
        // through export so isLandscape/outputSize stay correct for the
        // writer and PostCaptionView metadata.
        
        // Stop the delegate from feeding new frames
        captureDelegate?.isRecording = false
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        // Remove memory warning observer
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
            memoryWarningObserver = nil
        }
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
        
        // Pause frame capture
        captureDelegate?.isRecording = false
    }
    
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        
        // Resume wall-clock tracking from now
        recordingStartDate = Date()
        subjectSegmentStart = Date()
        
        // Resume frame capture
        captureDelegate?.isRecording = true
        captureDelegate?.isOnBreak = isOnBreak
        
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
    
    /// Finishes the timelapse writer — assembles stored frames into a
    /// 30-second video at 30fps.  Safe to call multiple times.
    func exportTimelapse() async -> URL? {
        if let existing = exportedVideoURL, timelapseWriter == nil {
            return existing
        }
        guard !isExporting else { return nil }
        guard let writer = timelapseWriter else { return nil }

        isExporting = true

        captureDelegate?.isRecording = false
        captureDelegate?.timelapseWriter = nil

        if let firstFrame = writer.firstFrameImage {
            thumbnailImage = UIImage(cgImage: firstFrame)
        }

        let videoURL = await writer.finish()
        timelapseWriter = nil

        isExporting = false
        exportedVideoURL = videoURL
        return videoURL
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
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
            memoryWarningObserver = nil
        }
        timelapseWriter?.cancel()
        timelapseWriter = nil
        captureDelegate?.timelapseWriter = nil
        captureSession.stopRunning()
    }
    
    // MARK: - Background Support
    
    /// Called when the app is about to enter the background
    func handleEnterBackground() {
        guard isRecording else { return }
        
        // Snapshot the current elapsed time and clear the start date.
        // When we return to foreground we'll set a new start date and
        // resume from the snapshotted value.  This avoids any drift from
        // Timer suspension in the background.
        backgroundDate = Date()
        if let start = recordingStartDate {
            elapsedBeforeCurrentStart = elapsedBeforeCurrentStart + Int(Date().timeIntervalSince(start))
        }
        recordingStartDate = nil
        
        // Stop timers — they won't fire in the background anyway
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        
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
                        captureDelegate?.isOnBreak = true
                    } else {
                        // A full break phase just completed — count it
                        totalBreakSeconds += phaseTime
                        pomodoroPhase = .study
                        pomodoroPhaseSecondsRemaining = pomodoroStudyMinutes * 60
                        isOnBreak = false
                        captureDelegate?.isOnBreak = false
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
        
        // Restart elapsed timer (frame capture resumes automatically via the delegate)
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        
        // Restart the capture session if it was interrupted — but only for
        // timelapse mode where frame capture is active.  In photo timer mode
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
