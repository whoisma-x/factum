//
//  TimelapseCameraView.swift
//  Pigeon
//
//  Timelapse recording with Pomodoro, set time, and continuous modes.
//  Supports wide-angle cameras and zoom control.
//

import SwiftUI
import SwiftData
import AVFoundation
import ActivityKit
import CallKit
import UserNotifications

// MARK: - Camera Phase

enum CameraPhase: Sendable {
    case timerSetup      // Pick timer mode + settings
    case cameraSetup     // Position camera, adjust zoom/flip
    case recording       // Active recording with timer display
    case photoCapture    // Take a photo before timer (photo timer mode)
    case photoConfirm    // Confirm photo, tap "Start Timer"
    case timerRunning    // Timer-only display, no camera preview (photo timer mode)
    case photoAfter      // Take a photo after timer ends
}

// MARK: - Unlock Animation Styles

enum UnlockAnimStyle: CaseIterable, Sendable {
    case pigeonFly       // Pigeon flies across and carries the lock away
    case lockShatter     // Lock shatters into pieces
    case lockMelt        // Lock melts downward
    case keyTurn         // Key inserts and turns
    case lockShrink      // Lock shrinks and pops
    case pigeonPeck      // Pigeon pecks the lock apart
}

// MARK: - Camera View

struct TimelapseCameraView: View {
    // Tutorial mode — when true, shows coach marks overlay for subjects + lock mode
    var isTutorialMode: Bool = false
    var onTutorialFinished: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \StudySubject.sortOrder) private var subjects: [StudySubject]
    @State private var captureManager = TimelapseCaptureManager()
    @State private var showPostCaption = false
    @State private var exportedVideoURL: URL?
    @State private var thumbnailData: Data?
    @State private var phase: CameraPhase = .timerSetup
    @State private var isExportingAndProceeding = false

    // Set time custom picker
    @State private var customHours = 1
    @State private var customMinutes = 0

    // Screen dimming during recording (visual overlay only — never touches hardware brightness)
    @AppStorage("autoDimScreen") private var autoDimEnabled = false
    @State private var isDimmed = false
    @State private var dimTimer: Timer?
    private let dimDelay: TimeInterval = 8.0
    
    // Photo timer mode
    @State private var isTakingPhoto = false
    @State private var photoBefore = false
    @State private var photoAfterEnabled = false
    @State private var lockMode = false
    @State private var unlockProgress: CGFloat = 0
    @State private var holdStartDate: Date?
    @State private var unlockTickTimer: Timer?
    @State private var unlockAnimStyle: UnlockAnimStyle = .pigeonFly
    @State private var showUnlockAnim = false
    
    /// Customisable hold-to-unlock duration (seconds). Persisted across sessions.
    @AppStorage("unlockHoldDuration") private var unlockHoldDuration: Double = 2.0
    
    // App-leave counter
    @State private var appLeaveCount: Int = 0
    @State private var totalOffTaskSeconds: Int = 0
    @State private var wasPhoneCall = false
    @State private var lastResignDate: Date?
    private let callObserver = CXCallObserver()
    
    // Live Activity for Dynamic Island timer
    @State private var studyActivity: Activity<StudySessionAttributes>?
    
    // Pinch-to-zoom baseline
    @State private var zoomAtGestureStart: CGFloat = 1.0
    @State private var showRecordFlash = false
    @State private var showLockTooltip = false
    @State private var showDiscardConfirm = false
    @State private var showSubjectPicker = false
    @State private var showAddSubject = false
    @State private var showSetupSubjectPicker = false
    
    // Camera tutorial state
    @State private var showCameraTutorialOverlay = false
    @State private var subjectPickerFrame: CGRect = .zero
    
    // Presence heartbeat during study sessions
    @State private var presenceTimer: Timer?
    
    /// Adaptive background for camera overlay elements:
    /// Light mode — translucent white (matches Start Recording style)
    /// Dark mode — translucent dark
    private var cameraOverlayBg: Color {
        colorScheme == .dark ? Color.black.opacity(0.4) : Color.white.opacity(0.25)
    }
    
    
    private var showsCameraPreview: Bool {
        phase == .cameraSetup || phase == .recording || phase == .photoCapture || phase == .photoAfter
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                cameraContent
                
                // Camera tutorial overlay (shown when opened from tutorial)
                if showCameraTutorialOverlay {
                    CameraTutorialOverlay(
                        isShowing: $showCameraTutorialOverlay,
                        onFinished: {
                            onTutorialFinished?()
                        },
                        subjectPickerFrame: subjectPickerFrame
                    )
                    .zIndex(200)
                }
            }
                .task {
                    await setupCamera()
                    // Request notification permission for study reminders
                    try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                }
                .onDisappear { handleDisappear() }
                .onChange(of: phase) { _, newPhase in handlePhaseChange(newPhase) }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in handleResignActive() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in handleBecomeActive() }
                .fullScreenCover(isPresented: $showPostCaption) { postCaptionSheet }
                .onChange(of: captureManager.isRecording) { _, newValue in handleRecordingChange(newValue) }
                .onChange(of: captureManager.currentSubject) { _, newSubject in
                    // Immediately broadcast subject change if actively studying
                    if phase == .recording || phase == .timerRunning {
                        let uid = AuthService.shared.currentUserID
                        guard !uid.isEmpty else { return }
                        Task {
                            await SupabaseService.shared.updatePresence(
                                uid: uid, isStudying: true, currentSubject: newSubject
                            )
                        }
                    }
                }
                .onAppear {
                    if isTutorialMode {
                        // Delay to let the setup screen render and report its frame
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showCameraTutorialOverlay = true
                        }
                    }
                }
        }
    }
    
    private func setupCamera() async {
        await captureManager.requestPermissionAndSetup()
        captureManager.startOrientationDetection()
    }
    
    private func handleDisappear() {
        cancelDimTimer()
        restoreBrightness()
        endLiveActivity()
        UIApplication.shared.isIdleTimerDisabled = false
        presenceTimer?.invalidate()
        presenceTimer = nil
        if !captureManager.isRecording {
            captureManager.cleanup()
        }
        // Clear study presence when leaving camera
        let uid = AuthService.shared.currentUserID
        if !uid.isEmpty {
            Task { await SupabaseService.shared.clearPresence(uid: uid) }
        }
    }
    
    private func handlePhaseChange(_ newPhase: CameraPhase) {
        UIApplication.shared.isIdleTimerDisabled = (newPhase == .recording || newPhase == .timerRunning || newPhase == .photoConfirm)
        // Restore brightness immediately when leaving recording/timer phases
        if newPhase != .recording && newPhase != .timerRunning {
            cancelDimTimer()
            restoreBrightness()
        }
        
        // Broadcast study presence
        let isStudying = (newPhase == .recording || newPhase == .timerRunning)
        let uid = AuthService.shared.currentUserID
        guard !uid.isEmpty else { return }
        
        if isStudying {
            // Start heartbeat every 2 minutes to keep online status alive
            presenceTimer?.invalidate()
            presenceTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
                Task {
                    await SupabaseService.shared.updatePresence(
                        uid: uid,
                        isStudying: true,
                        currentSubject: captureManager.currentSubject
                    )
                }
            }
        } else {
            presenceTimer?.invalidate()
            presenceTimer = nil
        }
        
        Task {
            await SupabaseService.shared.updatePresence(
                uid: uid,
                isStudying: isStudying,
                currentSubject: isStudying ? captureManager.currentSubject : nil
            )
        }
    }
    
    private func handleResignActive() {
        if phase == .recording || phase == .timerRunning {
            // Check if this resign is from a phone call (don't count as leaving)
            wasPhoneCall = callObserver.calls.contains { !$0.hasEnded }
            lastResignDate = Date()
            
            if lockMode || phase == .recording {
                // End session when leaving the app:
                //  - Always for lock mode (both camera & photo-timer)
                //  - Always for timelapse recording (camera) since the
                //    capture session can't run in the background
                // Request background time so the export can finish before
                // the system suspends the process.
                captureManager.handleEnterBackground()
                cancelDimTimer()
                restoreBrightness()
                captureManager.stopRecording()
                if phase == .timerRunning {
                    handleTimerEnd()
                } else {
                    exportAndProceed()
                }
            } else {
                captureManager.handleEnterBackground()
                // Show timer on Dynamic Island while the session continues in background
                startLiveActivity()
                // Send a notification reminding the user to come back
                if !wasPhoneCall {
                    sendStudyReminder()
                }
            }
        }
    }
    
    private func sendStudyReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Get back to studying!"
        content.body = "You left your \(captureManager.currentSubject) session. You've left \(appLeaveCount + 1) time\(appLeaveCount == 0 ? "" : "s") now."
        content.sound = .default
        
        // Fire after 3 seconds so it appears while they're in the other app
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: "study_reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    
    private func handleBecomeActive() {
        if phase == .recording || phase == .timerRunning {
            // Only count as a leave if gone for >= 2 seconds and not a phone call
            let awaySeconds = lastResignDate.map { Date().timeIntervalSince($0) } ?? 0
            if !wasPhoneCall && awaySeconds >= 2 {
                appLeaveCount += 1
                totalOffTaskSeconds += Int(awaySeconds)
            }
            wasPhoneCall = false
            lastResignDate = nil
            captureManager.handleEnterForeground()
            endLiveActivity()
            wakeScreen()
        }
    }
    
    private func handleRecordingChange(_ newValue: Bool) {
        if !newValue && captureManager.elapsedSeconds > 0 && !showPostCaption && !isExportingAndProceeding {
            if phase == .timerRunning {
                cancelDimTimer()
                restoreBrightness()
                handleTimerEnd()
            } else if phase == .recording {
                exportAndProceed()
            }
        }
    }
    
    /// Decides what happens when the timer-only session ends.
    /// Safe to call multiple times — subsequent calls are no-ops.
    private func handleTimerEnd() {
        // Guard against double entry: handleRecordingChange and handleResignActive
        // can both call this for the same recording stop event.
        guard !showPostCaption && !isExportingAndProceeding && phase != .photoAfter else { return }
        
        if photoAfterEnabled {
            // Set phase immediately (before async work) so the guard catches
            // any duplicate calls from onChange firing after the button tap.
            phase = .photoAfter
            // Restart camera preview for the after-photo
            Task {
                await captureManager.requestPermissionAndSetup()
            }
        } else {
            finishPhotoTimer()
        }
    }
    
    private var cameraContent: some View {
        cameraZStack
            .background(PigeonTheme.background)
            .gesture(magnifyGesture)
    }
    
    @ViewBuilder
    private var cameraZStack: some View {
        ZStack {
            PigeonTheme.background.ignoresSafeArea()
            
            if showsCameraPreview {
                CameraPreviewView(session: captureManager.captureSession,
                                  onDoubleTap: {
                    Haptics.light()
                    captureManager.flipCamera()
                    zoomAtGestureStart = captureManager.currentZoomFactor
                })
                    .ignoresSafeArea()
            }
            
            exportOverlay
            phaseOverlay
            recordFlashOverlay
            dimOverlay
        }
    }
    
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if showsCameraPreview {
                    captureManager.setZoom(zoomAtGestureStart * value.magnification)
                }
            }
            .onEnded { _ in
                if showsCameraPreview {
                    zoomAtGestureStart = captureManager.currentZoomFactor
                }
            }
    }
    
    private var postCaptionSheet: some View {
        let photos: [UIImage] = {
            let before = captureManager.beforePhoto
            let after = captureManager.capturedPhoto
            // If both exist and are different (before/after), show both; otherwise just the one
            if let b = before, let a = after, b !== a {
                return [b, a]
            }
            return [before ?? after].compactMap { $0 }
        }()
        return PostCaptionView(
            durationSeconds: captureManager.studySeconds,
            videoURL: exportedVideoURL,
            thumbnailData: thumbnailData,
            isLandscape: captureManager.isLandscape,
            capturedPhotos: photos,
            subjectSegments: captureManager.finalizedSegments(),
            appLeaveCount: appLeaveCount,
            offTaskSeconds: totalOffTaskSeconds,
            onComplete: {
                showPostCaption = false
                captureManager.cleanup()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    dismiss()
                }
            },
            onDiscard: {
                // Go back to the paused timer/timelapse
                showPostCaption = false
                isExportingAndProceeding = false
                // Ensure paused overlay shows so user can resume or re-end
                if !captureManager.isRecording {
                    // Auto-stop or stopRecording() already fired — restore paused state
                    captureManager.isRecording = true
                }
                captureManager.isPaused = true
            }
        )
    }
    
    // MARK: - Export Overlay
    
    @ViewBuilder
    private var exportOverlay: some View {
        if captureManager.isExporting {
            PigeonTheme.background.opacity(0.7)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(PigeonTheme.primaryText)
                    .scaleEffect(1.5)
                Text("Creating your timelapse...")
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
            }
        }
    }
    
    // MARK: - Flash & Dim Overlays
    
    private var recordFlashOverlay: some View {
        Color.white
            .ignoresSafeArea()
            .opacity(showRecordFlash ? 0.6 : 0)
            .animation(.easeOut(duration: 0.3), value: showRecordFlash)
            .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private var dimOverlay: some View {
        if (phase == .recording || phase == .timerRunning) && isDimmed {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    wakeScreen()
                }
        }
    }
    
    // MARK: - Phase Overlay
    
    @ViewBuilder
    private var phaseOverlay: some View {
        switch phase {
        case .timerSetup:
            timerSetupOverlay
                .transition(.move(edge: .leading).combined(with: .opacity))
        case .cameraSetup:
            cameraSetupOverlay
                .transition(.opacity)
        case .recording:
            recordingOverlay
                .transition(.opacity)
        case .photoCapture, .photoAfter:
            photoCaptureOverlay
                .transition(.opacity)
        case .photoConfirm:
            photoConfirmOverlay
                .transition(.opacity)
        case .timerRunning:
            timerRunningOverlay
                .transition(.opacity)
        }
    }
    
    // MARK: - Timer Setup Overlay
    
    private var timerSetupOverlay: some View {
        VStack {
            // Top bar
            HStack {
                Button {
                    captureManager.cleanup()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(PigeonTheme.primaryText)
                        .padding(12)
                        .background(PigeonTheme.elevated)
                        .clipShape(Circle())
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Spacer(minLength: 8)
            
            // Recording mode + timer selection
            VStack(spacing: 16) {
                // Recording mode toggle — custom styled
                HStack(spacing: 8) {
                    recordingModeButton(mode: .timelapse, label: "Timelapse")
                    recordingModeButton(mode: .photoTimer, label: "Timer")
                }
                .padding(.horizontal, 24)
                
                Text(captureManager.recordingMode == .timelapse ? "Choose Timelapse" : "Choose Timer")
                    .font(PigeonTheme.titleFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                
                // Mode cards
                VStack(spacing: 10) {
                    ForEach(TimerMode.allCases) { mode in
                        timerModeCard(mode: mode)
                    }
                }
                .padding(.horizontal, 24)
                
                // Mode-specific settings
                modeSettings
                    .padding(.horizontal, 24)

                // Auto-detected orientation indicator (themed for setup page)
                HStack(spacing: 6) {
                    Image(systemName: captureManager.detectedOrientation.icon)
                        .font(.system(size: 12))
                    Text(captureManager.detectedOrientation.displayLabel)
                        .font(PigeonTheme.font(12, weight: .semibold))
                }
                .foregroundStyle(PigeonTheme.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(PigeonTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: captureManager.detectedOrientation.isLandscape)
                .padding(.top, 4)
            }
            
            Spacer(minLength: 16)
            
            // Timer options (only for Timer mode)
            if captureManager.recordingMode == .photoTimer {
                VStack(spacing: 10) {
                    // Photo timing toggles
                    HStack(spacing: 8) {
                        optionToggle(label: "Photo Before", icon: "camera", isOn: $photoBefore)
                        optionToggle(label: "Photo After", icon: "camera.fill", isOn: $photoAfterEnabled)
                    }
                    
                }
                .padding(.horizontal, 24)
            }
            
            // Subject picker — tap to open selection sheet
            Button {
                showSetupSubjectPicker = true
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(StudySubject.color(for: captureManager.currentSubject, in: subjects))
                        .frame(width: 10, height: 10)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Subject")
                            .font(PigeonTheme.smallFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        Text(captureManager.currentSubject)
                            .font(PigeonTheme.subheadlineFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                .padding(PigeonTheme.spacing16)
                .background(PigeonTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: PigeonTheme.cornerField))
            }
            .padding(.horizontal, 24)
            .overlay {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { subjectPickerFrame = geo.frame(in: .global) }
                        .onChange(of: geo.size) { subjectPickerFrame = geo.frame(in: .global) }
                }
            }
            .sheet(isPresented: $showSetupSubjectPicker) {
                setupSubjectPickerSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(PigeonTheme.background)
            }
            .sheet(isPresented: $showAddSubject) {
                AddSubjectView()
            }
            
            // Next button
            Button {
                Haptics.light()
                // Apply custom time settings
                if captureManager.timerMode == .setTime {
                    captureManager.setTimeDurationMinutes = customHours * 60 + customMinutes
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    if captureManager.recordingMode == .photoTimer {
                        if photoBefore {
                            phase = .photoCapture
                        } else {
                            // No photo before — start timer directly
                            phase = .timerRunning
                            captureManager.startTimerOnly()
                            scheduleDim()
                        }
                    } else {
                        phase = .cameraSetup
                    }
                }
            } label: {
                Text("Next")
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(PigeonTheme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(PigeonTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
    }
    
    private func timerModeCard(mode: TimerMode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                captureManager.timerMode = mode
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: mode.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(captureManager.timerMode == mode ? PigeonTheme.accentText : PigeonTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(captureManager.timerMode == mode ? PigeonTheme.accent : PigeonTheme.elevated)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(PigeonTheme.subheadlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                    
                    Text(modeDescription(mode))
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
                
                Spacer()
                
                if captureManager.timerMode == mode {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(PigeonTheme.accent)
                }
            }
            .padding(14)
            .background(captureManager.timerMode == mode ? PigeonTheme.accent.opacity(0.5) : PigeonTheme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        captureManager.timerMode == mode ? PigeonTheme.accent : .clear,
                        lineWidth: 1.5
                    )
            )
        }
    }
    
    private func modeDescription(_ mode: TimerMode) -> String {
        switch mode {
        case .continuous: return "Record until you stop"
        case .pomodoro: return "25min study / 5min break cycles"
        case .setTime: return "Set a fixed duration"
        }
    }
    
    @ViewBuilder
    private var modeSettings: some View {
        switch captureManager.timerMode {
        case .continuous:
            EmptyView()
            
        case .pomodoro:
            VStack(spacing: 12) {
                HStack {
                    Text("Study")
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                    Spacer()
                    HStack(spacing: 8) {
                        stepButton(systemName: "minus") {
                            captureManager.pomodoroStudyMinutes = max(5, captureManager.pomodoroStudyMinutes - 5)
                        }
                        Text("\(captureManager.pomodoroStudyMinutes) min")
                            .font(PigeonTheme.font(16, weight: .semibold))
                            .foregroundStyle(PigeonTheme.primaryText)
                            .frame(width: 64)
                        stepButton(systemName: "plus") {
                            captureManager.pomodoroStudyMinutes = min(90, captureManager.pomodoroStudyMinutes + 5)
                        }
                    }
                }
                
                HStack {
                    Text("Break")
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                    Spacer()
                    HStack(spacing: 8) {
                        stepButton(systemName: "minus") {
                            captureManager.pomodoroBreakMinutes = max(1, captureManager.pomodoroBreakMinutes - 1)
                        }
                        Text("\(captureManager.pomodoroBreakMinutes) min")
                            .font(PigeonTheme.font(16, weight: .semibold))
                            .foregroundStyle(PigeonTheme.primaryText)
                            .frame(width: 64)
                        stepButton(systemName: "plus") {
                            captureManager.pomodoroBreakMinutes = min(30, captureManager.pomodoroBreakMinutes + 1)
                        }
                    }
                }
                
                HStack {
                    Text("Cycles")
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.secondaryText)
                    Spacer()
                    HStack(spacing: 8) {
                        stepButton(systemName: "minus") {
                            captureManager.pomodoroMaxCycles = max(0, captureManager.pomodoroMaxCycles - 1)
                        }
                        Text(captureManager.pomodoroMaxCycles == 0 ? "\u{221E}" : "\(captureManager.pomodoroMaxCycles)")
                            .font(PigeonTheme.font(16, weight: .semibold))
                            .foregroundStyle(PigeonTheme.primaryText)
                            .frame(width: 64)
                        stepButton(systemName: "plus") {
                            captureManager.pomodoroMaxCycles = min(20, captureManager.pomodoroMaxCycles + 1)
                        }
                    }
                }
            }
            .padding(16)
            .background(PigeonTheme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
        case .setTime:
            VStack(spacing: 12) {
                Text("Duration")
                    .font(PigeonTheme.bodyFont)
                    .foregroundStyle(PigeonTheme.secondaryText)
                
                HStack(spacing: 16) {
                    // Quick presets
                    ForEach([30, 60, 120, 180], id: \.self) { minutes in
                        let label = minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
                        let isSelected = (customHours * 60 + customMinutes) == minutes
                        
                        Button {
                            customHours = minutes / 60
                            customMinutes = minutes % 60
                        } label: {
                            Text(label)
                                .font(PigeonTheme.font(14, weight: .semibold))
                                .foregroundStyle(isSelected ? PigeonTheme.accentText : PigeonTheme.primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isSelected ? PigeonTheme.accent : PigeonTheme.elevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                
                // Custom time stepper
                HStack(spacing: 4) {
                    Spacer()
                    stepButton(systemName: "minus") {
                        let total = max(5, customHours * 60 + customMinutes - 5)
                        customHours = total / 60
                        customMinutes = total % 60
                    }
                    Text(String(format: "%dh %02dm", customHours, customMinutes))
                        .font(PigeonTheme.font(18, weight: .bold))
                        .foregroundStyle(PigeonTheme.primaryText)
                        .monospacedDigit()
                        .frame(width: 100)
                    stepButton(systemName: "plus") {
                        let total = min(480, customHours * 60 + customMinutes + 5)
                        customHours = total / 60
                        customMinutes = total % 60
                    }
                    Spacer()
                }
            }
            .padding(16)
            .background(PigeonTheme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(PigeonTheme.primaryText)
                .frame(width: 32, height: 32)
                .background(PigeonTheme.elevated)
                .clipShape(Circle())
        }
    }
    
    private func optionToggle(label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(PigeonTheme.font(13, weight: .semibold))
            }
            .foregroundStyle(isOn.wrappedValue ? PigeonTheme.accentText : PigeonTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isOn.wrappedValue ? PigeonTheme.accent : PigeonTheme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private func recordingModeButton(mode: RecordingMode, label: String) -> some View {
        let isSelected = captureManager.recordingMode == mode
        return Button {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                captureManager.recordingMode = mode
            }
        } label: {
            Text(label)
                .font(PigeonTheme.font(14, weight: .semibold))
                .foregroundStyle(isSelected ? PigeonTheme.accentText : PigeonTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? PigeonTheme.accent : PigeonTheme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? PigeonTheme.accent : .clear, lineWidth: 1.5)
                )
        }
    }
    
    // MARK: - Camera Setup Overlay
    
    private var cameraSetupOverlay: some View {
        VStack(spacing: 0) {
            // Top bar — minimal, dark chrome
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        phase = .timerSetup
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                
                Spacer()
                
                Spacer()
                
                // Orientation indicator — subtle
                orientationIndicator
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            Spacer()
            
            // Bottom chrome — Apple Camera style
            VStack(spacing: 20) {
                // Zoom level buttons
                zoomButtons
                
                // Timer mode summary pill
                timerModeSummary
                
                // Record button row — centered big red circle
                HStack {
                    // Empty spacer for balance
                    Color.clear.frame(width: 44, height: 44)
                    
                    Spacer()
                    
                    // Record button — Apple Camera style
                    Button {
                        Haptics.medium()
                        showRecordFlash = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showRecordFlash = false
                        }
                        captureManager.startRecording()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            phase = .recording
                        }
                        scheduleDim()
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(.white, lineWidth: 4)
                                .frame(width: 72, height: 72)
                            Circle()
                                .fill(.red)
                                .frame(width: 60, height: 60)
                        }
                    }
                    
                    Spacer()
                    
                    // Flip camera (secondary position)
                    Button {
                        Haptics.light()
                        captureManager.flipCamera()
                        zoomAtGestureStart = captureManager.currentZoomFactor
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 40)
            .padding(.top, 16)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }
    
    // MARK: - Timer Mode Summary
    
    private var timerModeSummary: some View {
        HStack(spacing: 6) {
            Image(systemName: captureManager.timerMode.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            
            Text(timerSummaryText)
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white.opacity(0.15))
        .clipShape(Capsule())
    }
    
    private var timerSummaryText: String {
        switch captureManager.timerMode {
        case .continuous:
            return "Continuous"
        case .pomodoro:
            return "Pomodoro \(captureManager.pomodoroStudyMinutes)m / \(captureManager.pomodoroBreakMinutes)m break"
        case .setTime:
            let total = captureManager.setTimeDurationMinutes
            if total >= 60 {
                let h = total / 60
                let m = total % 60
                return m > 0 ? "Set Time: \(h)h \(m)m" : "Set Time: \(h)h"
            }
            return "Set Time: \(total)m"
        }
    }
    
    // MARK: - Recording Overlay
    
    private var recordingOverlay: some View {
        ZStack {
            // Main recording UI
            VStack(spacing: 0) {
                Spacer()
                
                // Centre area — poster-style timer display
                VStack(spacing: 6) {
                    // Recording indicator — small red dot
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .padding(.bottom, 4)
                    
                    // Large elapsed time — tall serif, poster-style
                    Text(formatTime(captureManager.elapsedSeconds))
                        .font(.system(size: 52, weight: .ultraLight, design: .serif))
                        .foregroundStyle(.white)
                        .tracking(2)
                    
                    // Mode-specific info (pomodoro phase, countdown, etc.)
                    recordingModeInfo
                    
                    // Subject pill — always visible, tappable only when unlocked
                    subjectPill(isCamera: true)
                        .padding(.top, 6)
                        .allowsHitTesting(!lockMode)
                        .opacity(lockMode ? 0.6 : 1.0)
                    
                    // App leave counter as small badge
                    if appLeaveCount > 0 {
                        leaveCounter(isCamera: true)
                    }
                }
                
                Spacer()
                
                // Bottom chrome
                if lockMode {
                    // Locked: hold-to-unlock centered at bottom, no gradient
                    VStack(spacing: 16) {
                        holdToUnlockControl(isCamera: true)
                    }
                    .padding(.bottom, 40)
                    .padding(.top, 12)
                } else {
                    VStack(spacing: 16) {
                        // Zoom level buttons
                        zoomButtons
                        
                        // Lock button — small, above controls
                        lockButton
                        
                        // Control row — pause, stop, flip
                        HStack {
                            Button {
                                Haptics.light()
                                cancelDimTimer()
                                restoreBrightness()
                                captureManager.pauseRecording()
                            } label: {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                            }
                            
                            Spacer()
                            
                            // Stop button — Apple Camera style (square in circle)
                            Button {
                                Haptics.medium()
                                cancelDimTimer()
                                restoreBrightness()
                                captureManager.stopRecording()
                                exportAndProceed()
                            } label: {
                                ZStack {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 4)
                                        .frame(width: 72, height: 72)
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.red)
                                        .frame(width: 30, height: 30)
                                }
                            }
                            .disabled(captureManager.isExporting)
                            
                            Spacer()
                            
                            // Flip camera (right)
                            Button {
                                Haptics.light()
                                captureManager.flipCamera()
                                zoomAtGestureStart = captureManager.currentZoomFactor
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 40)
                    .padding(.top, 12)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .bottom)
                    )
                }
            }
            .opacity(captureManager.isExporting ? 0.3 : 1.0)
            .allowsHitTesting(!captureManager.isExporting)
            
            // Paused overlay
            if captureManager.isPaused {
                pausedOverlay(isCamera: true)
            }
        }
    }
    
    // MARK: - Recording Mode Info (poster-style, shown below timer)
    
    @ViewBuilder
    private var recordingModeInfo: some View {
        switch captureManager.timerMode {
        case .continuous:
            EmptyView()
            
        case .pomodoro:
            VStack(spacing: 6) {
                // Phase label
                Text(captureManager.pomodoroPhase.rawValue.uppercased())
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .tracking(3)
                    .foregroundStyle(captureManager.isOnBreak ? .green : .white.opacity(0.5))
                
                // Phase remaining — large
                Text(formatTime(captureManager.pomodoroPhaseSecondsRemaining))
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .foregroundStyle(captureManager.isOnBreak ? .green : .white.opacity(0.7))
                
                // Cycle count
                Text(
                    captureManager.pomodoroMaxCycles > 0
                        ? "\(captureManager.pomodoroCompletedCycles)/\(captureManager.pomodoroMaxCycles) cycles"
                        : "\(captureManager.pomodoroCompletedCycles) cycles"
                )
                .font(.system(size: 11, weight: .light, design: .serif))
                .foregroundStyle(.white.opacity(0.3))
                
                if captureManager.isOnBreak {
                    Text("BREAK")
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .tracking(2)
                        .foregroundStyle(.green.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            
        case .setTime:
            VStack(spacing: 4) {
                Text(formatTime(captureManager.countdownSecondsRemaining))
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .foregroundStyle(captureManager.countdownSecondsRemaining < 60 ? .orange : .white.opacity(0.6))
                
                Text("remaining")
                    .font(.system(size: 10, weight: .light, design: .serif))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }
    
    // MARK: - Timer Display
    
    private var pomodoroPhaseProgress: Double {
        let totalPhaseSeconds = captureManager.isOnBreak
            ? captureManager.pomodoroBreakMinutes * 60
            : captureManager.pomodoroStudyMinutes * 60
        guard totalPhaseSeconds > 0 else { return 0 }
        let elapsed = totalPhaseSeconds - captureManager.pomodoroPhaseSecondsRemaining
        return Double(elapsed) / Double(totalPhaseSeconds)
    }
    
    private var setTimeProgress: Double {
        let totalSeconds = captureManager.setTimeDurationMinutes * 60
        guard totalSeconds > 0 else { return 0 }
        return Double(captureManager.elapsedSeconds) / Double(totalSeconds)
    }
    
    @ViewBuilder
    private var timerDisplay: some View {
        VStack(spacing: 12) {
            switch captureManager.timerMode {
            case .continuous:
                VStack(spacing: 8) {
                    // Breathing ring — smaller, accent only
                    BreathingRing(ringColor: .white, trackColor: .white.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    // Large poster-style time
                    Text(formatTime(captureManager.elapsedSeconds))
                        .font(.system(size: 56, weight: .ultraLight, design: .serif))
                        .foregroundStyle(.white)
                        .tracking(2)
                    
                    Text(captureManager.isRecording ? "RECORDING" : "TAP TO START")
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.4))
                }
                
            case .pomodoro:
                VStack(spacing: 8) {
                    // Phase label
                    Text(captureManager.pomodoroPhase.rawValue.uppercased())
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .tracking(3)
                        .foregroundStyle(captureManager.isOnBreak ? .green : .white.opacity(0.5))
                    
                    // Phase remaining — large poster
                    Text(formatTime(captureManager.pomodoroPhaseSecondsRemaining))
                        .font(.system(size: 56, weight: .ultraLight, design: .serif))
                        .foregroundStyle(captureManager.isOnBreak ? .green : .white)
                        .tracking(2)
                    
                    // Thin progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(.white.opacity(0.12))
                                .frame(height: 2)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(captureManager.isOnBreak ? .green : .white.opacity(0.6))
                                .frame(width: geo.size.width * pomodoroPhaseProgress, height: 2)
                                .animation(.linear(duration: 1), value: pomodoroPhaseProgress)
                        }
                    }
                    .frame(width: 120, height: 2)
                    .padding(.vertical, 4)
                    
                    // Cycle count + total time
                    Text(
                        captureManager.pomodoroMaxCycles > 0
                            ? "\(captureManager.pomodoroCompletedCycles)/\(captureManager.pomodoroMaxCycles) CYCLES"
                            : "\(captureManager.pomodoroCompletedCycles) CYCLES"
                    )
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.35))
                    
                    Text(formatTime(captureManager.elapsedSeconds))
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1)
                    
                    if captureManager.isOnBreak {
                        Text("BREAK")
                            .font(.system(size: 10, weight: .regular, design: .serif))
                            .tracking(2)
                            .foregroundStyle(.green.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                
            case .setTime:
                VStack(spacing: 8) {
                    // Countdown — large poster
                    Text(formatTime(captureManager.countdownSecondsRemaining))
                        .font(.system(size: 56, weight: .ultraLight, design: .serif))
                        .foregroundStyle(captureManager.countdownSecondsRemaining < 60 ? .orange : .white)
                        .tracking(2)
                    
                    // Thin progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(.white.opacity(0.12))
                                .frame(height: 2)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(captureManager.countdownSecondsRemaining < 60 ? .orange.opacity(0.7) : .white.opacity(0.6))
                                .frame(width: geo.size.width * setTimeProgress, height: 2)
                                .animation(.linear(duration: 1), value: setTimeProgress)
                        }
                    }
                    .frame(width: 120, height: 2)
                    .padding(.vertical, 4)
                    
                    Text("REMAINING")
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.35))
                    
                    Text(formatTime(captureManager.elapsedSeconds))
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1)
                }
            }
        }
    }
    
    // MARK: - Zoom Buttons (Apple Camera style)
    
    /// Zoom level buttons derived from the device's actual lens configuration.
    /// Shows buttons like [.5] [1] [3] matching Apple Camera exactly.
    private var zoomButtons: some View {
        let levels = availableZoomLevels
        let closest = closestZoomLevel(from: levels)
        
        return HStack(spacing: 2) {
            ForEach(levels, id: \.label) { level in
                let isSelected = level.deviceFactor == closest
                let isIntermediate = isSelected
                    && abs(captureManager.currentZoomFactor - level.deviceFactor) > 0.05
                let displayText = isIntermediate
                    ? formatZoomLabel(displayZoomValue)
                    : level.label
                let size: CGFloat = isSelected ? 33 : 28
                
                Text(displayText)
                    .font(.system(size: isSelected ? 12 : 10,
                                  weight: .semibold, design: .serif))
                    .foregroundStyle(isSelected
                        ? Color(red: 1.0, green: 0.84, blue: 0.04)
                        : .white.opacity(0.6))
                    .frame(width: size, height: size)
                    .background(.black.opacity(isSelected ? 0.55 : 0.4))
                    .clipShape(Circle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            captureManager.setZoom(level.deviceFactor, animated: true)
                            zoomAtGestureStart = level.deviceFactor
                        }
                    }
                    .animation(.spring(response: 0.25, dampingFraction: 0.8),
                               value: isSelected)
            }
        }
    }
    
    /// Zoom levels derived from the device's actual lens configuration,
    /// using Apple's `displayVideoZoomFactorMultiplier` for correct labels
    /// on every phone model (e.g. iPhone 15 Pro shows .5/1/3, 
    /// iPhone 15 Pro Max shows .5/1/5).
    private var availableZoomLevels: [(label: String, deviceFactor: CGFloat)] {
        let m = captureManager.displayZoomMultiplier
        var levels: [(label: String, deviceFactor: CGFloat)] = []
        
        // Ultra-wide — at device minimum zoom
        if captureManager.hasUltraWide {
            let displayVal = captureManager.minZoomFactor * m
            let label = formatZoomButton(displayVal)
            levels.append((label, captureManager.minZoomFactor))
        }
        
        // Wide-angle — at the first switch-over point
        let w = captureManager.wideAngleZoomFactor
        let wideDisplay = w * m
        levels.append((formatZoomButton(wideDisplay), w))
        
        // Additional lenses from remaining switch-over factors
        let switchOvers = captureManager.switchOverFactors
        for i in switchOvers.indices where i >= 1 {
            let deviceFactor = switchOvers[i]
            let displayVal = deviceFactor * m
            levels.append((formatZoomButton(displayVal), deviceFactor))
        }
        
        return levels
    }
    
    /// Current zoom as Apple-style display value using the device's multiplier.
    private var displayZoomValue: CGFloat {
        captureManager.currentZoomFactor * captureManager.displayZoomMultiplier
    }
    
    /// Format a display zoom value for a button label.
    /// Apple Camera style: 0.5 → ".5", 1.0 → "1", 3.0 → "3", 2.5 → "2.5"
    private func formatZoomButton(_ displayValue: CGFloat) -> String {
        let val = (displayValue * 10).rounded() / 10 // round to 1 decimal
        let isWhole = abs(val - val.rounded()) < 0.05
        if isWhole {
            let intVal = Int(val.rounded())
            if intVal == 0 { return ".5" }
            return "\(intVal)"
        }
        // Fractional — format with 1 decimal, drop leading zero if < 1
        let str = String(format: "%.1f", val)
        if val < 1.0 && str.hasPrefix("0") {
            return String(str.dropFirst()) // "0.5" → ".5"
        }
        return str
    }
    
    /// Finds which zoom level button is closest to the current device zoom factor.
    private func closestZoomLevel(
        from levels: [(label: String, deviceFactor: CGFloat)]
    ) -> CGFloat {
        let current = captureManager.currentZoomFactor
        return levels.min(by: {
            abs(log2($0.deviceFactor) - log2(current))
                < abs(log2($1.deviceFactor) - log2(current))
        })?.deviceFactor ?? 1.0
    }
    
    /// Format zoom label like "1.5×" for intermediate display values.
    private func formatZoomLabel(_ displayFactor: CGFloat) -> String {
        if abs(displayFactor - displayFactor.rounded()) < 0.05 {
            return "\(Int(displayFactor.rounded()))×"
        }
        return String(format: "%.1f×", displayFactor)
    }
    
    // MARK: - Orientation Indicator

    /// Passive indicator showing the auto-detected device orientation.
    private var orientationIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: captureManager.detectedOrientation.icon)
                .font(.system(size: 11))
            Text(captureManager.detectedOrientation.displayLabel)
                .font(.system(size: 11, weight: .semibold, design: .serif))
        }
        .foregroundStyle(.white.opacity(0.5))
        .animation(.easeInOut(duration: 0.2), value: captureManager.detectedOrientation.isLandscape)
    }

    // MARK: - Photo Capture Overlay
    
    private var photoCaptureOverlay: some View {
        VStack {
            // Top bar
            HStack {
                Button {
                    if phase == .photoAfter {
                        // Skip the after-photo — post with whatever we have
                        finishPhotoTimer()
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            phase = .timerSetup
                        }
                    }
                } label: {
                    Image(systemName: phase == .photoAfter ? "xmark" : "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(cameraOverlayBg)
                        .clipShape(Circle())
                }
                
                Spacer()
                
                Text(phase == .photoAfter ? "Take Your Photo" : "Take a Photo")
                    .font(PigeonTheme.subheadlineFont)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(cameraOverlayBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Spacer()
                
                // Flip camera
                Button {
                    Haptics.light()
                    captureManager.flipCamera()
                    zoomAtGestureStart = captureManager.currentZoomFactor
                } label: {
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(cameraOverlayBg)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Spacer()
            
            // Bottom controls
            VStack(spacing: 16) {
                // Zoom level buttons
                zoomButtons
                
                // Timer mode summary
                timerModeSummary
                
                // Shutter button
                Button {
                    Haptics.medium()
                    takePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .fill(.white)
                            .frame(width: 66, height: 66)
                    }
                }
                .disabled(isTakingPhoto)
                .opacity(isTakingPhoto ? 0.5 : 1.0)
                .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Photo Confirm Overlay
    
    private var photoConfirmOverlay: some View {
        VStack {
            // Top bar
            HStack {
                Button {
                    Haptics.light()
                    captureManager.capturedPhoto = nil
                    captureManager.beforePhoto = nil
                    thumbnailData = nil
                    withAnimation(.easeInOut(duration: 0.3)) {
                        phase = .photoCapture
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Retake")
                            .font(PigeonTheme.font(14, weight: .semibold))
                    }
                    .foregroundStyle(PigeonTheme.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(PigeonTheme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Spacer()
            
            // Photo preview
            if let photo = captureManager.capturedPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 260, maxHeight: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            }
            
            Spacer()
            
            // Start Timer button
            Button {
                Haptics.medium()
                startTimerFromConfirm()
            } label: {
                Text("Start Timer")
                    .font(PigeonTheme.font(18, weight: .semibold))
                    .foregroundStyle(PigeonTheme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(PigeonTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
    }
    
    // MARK: - Timer Running Overlay
    
    private var timerRunningOverlay: some View {
        ZStack {
            VStack {
                // Top bar
                HStack {
                    if !lockMode {
                        Button {
                            Haptics.light()
                            cancelDimTimer()
                            restoreBrightness()
                            captureManager.pauseRecording()
                        } label: {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(PigeonTheme.primaryText)
                                .padding(12)
                                .background(PigeonTheme.elevated)
                                .clipShape(Circle())
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Spacer()
                
                // Photo thumbnail
                if let photo = captureManager.capturedPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(PigeonTheme.accent, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        .padding(.bottom, 12)
                }
                
                // Timer display — themed for non-camera background
                photoTimerDisplay
                
                // Subject pill — always visible, tappable only when unlocked
                subjectPill(isCamera: false)
                    .padding(.top, 8)
                    .allowsHitTesting(!lockMode)
                    .opacity(lockMode ? 0.6 : 1.0)
                
                // Lock toggle or hold-to-unlock
                if lockMode {
                    holdToUnlockControl(isCamera: false)
                        .padding(.top, 12)
                } else {
                    lockButton
                        .padding(.top, 12)
                }
                
                // App leave counter
                if appLeaveCount > 0 {
                    leaveCounter(isCamera: false)
                        .padding(.top, 8)
                }
                
                Spacer()
                
                // End Session button — only when unlocked
                if !lockMode {
                    Button {
                        Haptics.medium()
                        cancelDimTimer()
                        restoreBrightness()
                        captureManager.stopRecording()
                        handleTimerEnd()
                    } label: {
                        Text("End Session")
                            .font(PigeonTheme.font(18, weight: .semibold))
                            .foregroundStyle(PigeonTheme.accentText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(PigeonTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50)
                }
            }
            
            // Paused overlay
            if captureManager.isPaused {
                pausedOverlay(isCamera: false)
            }
        }
    }
    
    // MARK: - Photo Timer Display
    
    @ViewBuilder
    private var photoTimerDisplay: some View {
        VStack(spacing: 12) {
            switch captureManager.timerMode {
            case .continuous:
                VStack(spacing: 8) {
                    // Breathing ring — smaller accent
                    BreathingRing(ringColor: PigeonTheme.accent, trackColor: PigeonTheme.elevated)
                        .frame(width: 80, height: 80)
                    
                    // Large poster-style time
                    Text(formatTime(captureManager.elapsedSeconds))
                        .font(.system(size: 56, weight: .ultraLight, design: .serif))
                        .foregroundStyle(PigeonTheme.primaryText)
                        .tracking(2)
                    
                    Text("STUDYING")
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .tracking(3)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                }
                
            case .pomodoro:
                VStack(spacing: 8) {
                    // Phase label
                    Text(captureManager.pomodoroPhase.rawValue.uppercased())
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .tracking(3)
                        .foregroundStyle(captureManager.isOnBreak ? .green : PigeonTheme.tertiaryText)
                    
                    // Phase remaining — large poster
                    Text(formatTime(captureManager.pomodoroPhaseSecondsRemaining))
                        .font(.system(size: 56, weight: .ultraLight, design: .serif))
                        .foregroundStyle(captureManager.isOnBreak ? .green : PigeonTheme.primaryText)
                        .tracking(2)
                    
                    // Thin progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(PigeonTheme.separator)
                                .frame(height: 2)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(captureManager.isOnBreak ? .green : PigeonTheme.accent)
                                .frame(width: geo.size.width * pomodoroPhaseProgress, height: 2)
                                .animation(.linear(duration: 1), value: pomodoroPhaseProgress)
                        }
                    }
                    .frame(width: 120, height: 2)
                    .padding(.vertical, 4)
                    
                    // Cycle count
                    Text(
                        captureManager.pomodoroMaxCycles > 0
                            ? "\(captureManager.pomodoroCompletedCycles)/\(captureManager.pomodoroMaxCycles) CYCLES"
                            : "\(captureManager.pomodoroCompletedCycles) CYCLES"
                    )
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .tracking(2)
                    .foregroundStyle(PigeonTheme.tertiaryText)
                    
                    Text(formatTime(captureManager.elapsedSeconds))
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(PigeonTheme.secondaryText)
                        .tracking(1)
                    
                    if captureManager.isOnBreak {
                        Text("BREAK")
                            .font(.system(size: 10, weight: .regular, design: .serif))
                            .tracking(2)
                            .foregroundStyle(.green.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                
            case .setTime:
                VStack(spacing: 8) {
                    // Countdown — large poster
                    Text(formatTime(captureManager.countdownSecondsRemaining))
                        .font(.system(size: 56, weight: .ultraLight, design: .serif))
                        .foregroundStyle(captureManager.countdownSecondsRemaining < 60 ? .orange : PigeonTheme.primaryText)
                        .tracking(2)
                    
                    // Thin progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(PigeonTheme.separator)
                                .frame(height: 2)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(captureManager.countdownSecondsRemaining < 60 ? .orange.opacity(0.7) : PigeonTheme.accent)
                                .frame(width: geo.size.width * setTimeProgress, height: 2)
                                .animation(.linear(duration: 1), value: setTimeProgress)
                        }
                    }
                    .frame(width: 120, height: 2)
                    .padding(.vertical, 4)
                    
                    Text("REMAINING")
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .tracking(3)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                    
                    Text(formatTime(captureManager.elapsedSeconds))
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(PigeonTheme.secondaryText)
                        .tracking(1)
                }
            }
        }
    }
    
    // MARK: - Photo Timer Actions
    
    private func takePhoto() {
        isTakingPhoto = true
        showRecordFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showRecordFlash = false
        }
        Task {
            let photo = await captureManager.capturePhoto()
            
            if phase == .photoAfter {
                // After-photo — store separately, keep before-photo intact
                captureManager.capturedPhoto = photo
                finishPhotoTimer()
            } else {
                // Before-photo — store as both capturedPhoto (for preview) and beforePhoto (for post)
                captureManager.capturedPhoto = photo
                captureManager.beforePhoto = photo
                thumbnailData = photo?.jpegData(compressionQuality: 0.8)
                withAnimation(.easeInOut(duration: 0.3)) {
                    phase = .photoConfirm
                }
            }
            isTakingPhoto = false
        }
    }
    
    private func startTimerFromConfirm() {
        captureManager.startTimerOnly()
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .timerRunning
        }
        scheduleDim()
    }
    
    private func finishPhotoTimer() {
        guard !isExportingAndProceeding else { return }
        isExportingAndProceeding = true
        
        cancelDimTimer()
        restoreBrightness()
        
        // No video to export — go straight to post caption
        exportedVideoURL = nil
        showPostCaption = true
        isExportingAndProceeding = false
    }
    
    // MARK: - Subject Pill (shown during recording/timer)
    
    /// Tappable pill showing "Now studying: Subject" with the subject's color.
    private func subjectPill(isCamera: Bool) -> some View {
        Button {
            showSubjectPicker = true
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(StudySubject.color(for: captureManager.currentSubject, in: subjects))
                    .frame(width: 8, height: 8)
                Text(captureManager.currentSubject)
                    .font(PigeonTheme.font(13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(isCamera ? .white : PigeonTheme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isCamera ? Color.black.opacity(0.4) : PigeonTheme.elevated)
            .clipShape(Capsule())
        }
        .sheet(isPresented: $showSubjectPicker) {
            subjectSwitchSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(PigeonTheme.background)
        }
    }
    
    private var subjectSwitchSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(subjects) { studySubject in
                        Button {
                            captureManager.switchSubject(to: studySubject.name)
                            showSubjectPicker = false
                            // Re-schedule dim since user interacted
                            if phase == .recording || phase == .timerRunning {
                                scheduleDim()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(studySubject.color)
                                    .frame(width: 12, height: 12)
                                Text(studySubject.name)
                                    .font(PigeonTheme.bodyFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                                Spacer()
                                if captureManager.currentSubject == studySubject.name {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(PigeonTheme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                captureManager.currentSubject == studySubject.name
                                ? studySubject.color.opacity(0.15)
                                : PigeonTheme.cardBackground
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Switch Subject")
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSubjectPicker = false }
                        .foregroundStyle(PigeonTheme.accent)
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    // MARK: - Setup Subject Picker Sheet
    
    /// Subject picker used on the setup screen (before recording starts).
    private var setupSubjectPickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(subjects) { studySubject in
                        Button {
                            captureManager.currentSubject = studySubject.name
                            showSetupSubjectPicker = false
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(studySubject.color)
                                    .frame(width: 12, height: 12)
                                Text(studySubject.name)
                                    .font(PigeonTheme.bodyFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                                Spacer()
                                if captureManager.currentSubject == studySubject.name {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(PigeonTheme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                captureManager.currentSubject == studySubject.name
                                ? studySubject.color.opacity(0.15)
                                : PigeonTheme.cardBackground
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    // Add new subject button
                    Button {
                        showSetupSubjectPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showAddSubject = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(PigeonTheme.accent)
                            Text("New Subject")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.accent)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(PigeonTheme.separator, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Select Subject")
                        .font(PigeonTheme.headlineFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSetupSubjectPicker = false }
                        .foregroundStyle(PigeonTheme.accent)
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    // MARK: - Lock Button
    
    private var lockButton: some View {
        let isOnCamera = phase == .recording
        
        return Button {
            Haptics.medium()
            withAnimation(.easeInOut(duration: 0.25)) {
                lockMode = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.open")
                    .font(.system(size: 12, weight: .semibold))
                Text("Lock")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
            }
            .foregroundStyle(isOnCamera ? .white.opacity(0.55) : PigeonTheme.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isOnCamera ? .white.opacity(0.12) : PigeonTheme.elevated)
            .clipShape(Capsule())
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    showLockTooltip = true
                }
        )
        .alert("Lock Mode", isPresented: $showLockTooltip) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Ends your session and saves your progress when you leave the app. Hides all controls — hold to unlock.")
        }
    }
    
    // MARK: - Hold to Unlock Control
    
    private func holdToUnlockControl(isCamera: Bool) -> some View {
        let labelColor: Color = isCamera ? .white.opacity(0.25) : PigeonTheme.tertiaryText
        let trackColor: Color = isCamera ? .white.opacity(0.08) : PigeonTheme.separator
        let progressColor: Color = isCamera ? .white.opacity(0.7) : PigeonTheme.primaryText
        let iconColor: Color = isCamera ? .white.opacity(0.35) : PigeonTheme.tertiaryText
        let holdDuration = unlockHoldDuration
        
        return ZStack {
            // Normal hold-to-unlock UI
            if !showUnlockAnim {
                VStack(spacing: 20) {
                    // Lock icon — large, centered
                    Image(systemName: unlockProgress >= 1.0 ? "lock.open" : "lock.fill")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(unlockProgress >= 1.0 ? progressColor : iconColor)
                        .contentTransition(.symbolEffect(.replace))
                    
                    // "LOCKED" label — tall serif
                    Text("LOCKED")
                        .font(.system(size: 11, weight: .regular, design: .serif))
                        .tracking(4)
                        .foregroundStyle(labelColor)
                    
                    // Progress bar — horizontal, thin, elegant
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(trackColor)
                            .frame(width: 120, height: 3)
                        
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(progressColor)
                            .frame(width: 120 * unlockProgress, height: 3)
                    }
                    
                    // Instruction
                    Text(unlockProgress > 0 ? "" : "hold to unlock")
                        .font(.system(size: 10, weight: .light, design: .serif))
                        .tracking(1)
                        .foregroundStyle(labelColor)
                        .frame(height: 14)
                }
                .transition(.opacity)
            }
            
            // Unlock animation overlay
            if showUnlockAnim {
                unlockAnimationView(isCamera: isCamera)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .padding(.vertical, 24)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if holdStartDate == nil && !showUnlockAnim {
                        holdStartDate = Date()
                        Haptics.light()
                        withAnimation(.linear(duration: holdDuration)) {
                            unlockProgress = 1.0
                        }
                        // Haptic ticks every 0.4s while holding
                        unlockTickTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                            Haptics.selection()
                        }
                    }
                }
                .onEnded { _ in
                    unlockTickTimer?.invalidate()
                    unlockTickTimer = nil
                    if let start = holdStartDate, Date().timeIntervalSince(start) >= holdDuration {
                        Haptics.success()
                        // Pick random animation and play it
                        unlockAnimStyle = UnlockAnimStyle.allCases.randomElement() ?? .pigeonFly
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showUnlockAnim = true
                        }
                        unlockProgress = 0
                        // After animation plays, actually unlock
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                lockMode = false
                                showUnlockAnim = false
                            }
                        }
                    } else {
                        Haptics.light()
                        withAnimation(.easeOut(duration: 0.3)) {
                            unlockProgress = 0
                        }
                    }
                    holdStartDate = nil
                }
        )
    }
    
    // MARK: - Unlock Animation Views
    
    @ViewBuilder
    private func unlockAnimationView(isCamera: Bool) -> some View {
        let fg: Color = isCamera ? .white : PigeonTheme.primaryText
        let fg2: Color = isCamera ? .white.opacity(0.5) : PigeonTheme.secondaryText
        
        switch unlockAnimStyle {
        case .pigeonFly:
            UnlockAnim_PigeonFly(fg: fg, fg2: fg2)
        case .lockShatter:
            UnlockAnim_LockShatter(fg: fg, fg2: fg2)
        case .lockMelt:
            UnlockAnim_LockMelt(fg: fg, fg2: fg2)
        case .keyTurn:
            UnlockAnim_KeyTurn(fg: fg, fg2: fg2)
        case .lockShrink:
            UnlockAnim_LockShrink(fg: fg, fg2: fg2)
        case .pigeonPeck:
            UnlockAnim_PigeonPeck(fg: fg, fg2: fg2)
        }
    }
    
    // MARK: - Leave Counter
    
    private func leaveCounter(isCamera: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 10))
            Text("Left \(appLeaveCount)×")
                .font(.system(size: 11, weight: .medium, design: .serif))
            if totalOffTaskSeconds > 0 {
                Text("·")
                    .font(.system(size: 11, weight: .medium))
                Text(formatOffTaskTime(totalOffTaskSeconds))
                    .font(.system(size: 11, weight: .medium, design: .serif))
            }
        }
        .foregroundStyle(isCamera ? .white.opacity(0.4) : PigeonTheme.tertiaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isCamera ? .white.opacity(0.1) : PigeonTheme.elevated)
        .clipShape(Capsule())
    }
    
    private func formatOffTaskTime(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s off-task"
        }
        let mins = seconds / 60
        let secs = seconds % 60
        return secs > 0 ? "\(mins)m \(secs)s off-task" : "\(mins)m off-task"
    }
    
    // MARK: - Paused Overlay
    
    private func pausedOverlay(isCamera: Bool) -> some View {
        ZStack {
            // Frosted dark background
            (isCamera ? Color.black.opacity(0.8) : PigeonTheme.background.opacity(0.95))
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                Spacer()
                
                // Paused indicator — poster-style
                VStack(spacing: 16) {
                    Text("PAUSED")
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .tracking(4)
                        .foregroundStyle(isCamera ? .white.opacity(0.4) : PigeonTheme.tertiaryText)
                    
                    Text(formatTime(captureManager.elapsedSeconds))
                        .font(.system(size: 64, weight: .ultraLight, design: .serif))
                        .foregroundStyle(isCamera ? .white : PigeonTheme.primaryText)
                        .tracking(3)
                    
                    Image(systemName: "pause.fill")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(isCamera ? .white.opacity(0.3) : PigeonTheme.tertiaryText)
                }
                
                Spacer()
                
                // Controls at bottom — Apple Camera style
                VStack(spacing: 16) {
                    // Resume button — large, prominent
                    Button {
                        Haptics.medium()
                        captureManager.resumeRecording()
                        scheduleDim()
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(isCamera ? .white : PigeonTheme.primaryText, lineWidth: 4)
                                .frame(width: 72, height: 72)
                            Image(systemName: "play.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(isCamera ? .white : PigeonTheme.primaryText)
                        }
                    }
                    
                    // End Session
                    Button {
                        Haptics.medium()
                        if phase == .timerRunning {
                            handleTimerEnd()
                        } else {
                            exportAndProceed()
                        }
                    } label: {
                        Text("End Session")
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundStyle(isCamera ? .white.opacity(0.6) : PigeonTheme.secondaryText)
                    }
                    
                    // Discard
                    Button {
                        Haptics.warning()
                        showDiscardConfirm = true
                    } label: {
                        Text("Discard")
                            .font(.system(size: 13, weight: .medium, design: .serif))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: captureManager.isPaused)
        .alert("End session without posting?", isPresented: $showDiscardConfirm) {
            Button("End Session", role: .destructive) {
                // Save a final snapshot before cleanup so the session is
                // recovered on next app launch. Study time is never lost.
                captureManager.stopRecording()
                captureManager.saveSessionSnapshot()
                // Cleanup without clearing the snapshot — next launch will recover it
                captureManager.cleanupWithoutClearingSnapshot()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your study time will be saved and recovered next time you open the app.")
        }
    }
    
    // MARK: - Helpers

    private func exportAndProceed() {
        // Prevent double calls from stop button + onChange both firing
        guard !isExportingAndProceeding else { return }
        isExportingAndProceeding = true
        
        cancelDimTimer()
        restoreBrightness()
        Task {
            let url = await captureManager.exportTimelapse()
            exportedVideoURL = url
            // Always grab the thumbnail so the user can still post even if
            // video assembly failed (e.g. after a very long session).
            thumbnailData = captureManager.thumbnailImage?.jpegData(compressionQuality: 0.8)
            // Always show post screen — the user already invested study time.
            // If video is nil, the post is photo/stats only rather than lost entirely.
            showPostCaption = true
            isExportingAndProceeding = false
        }
    }
    
    private func formatTime(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    // MARK: - Live Activity (Dynamic Island)
    
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = StudySessionAttributes(
            subject: captureManager.currentSubject,
            startDate: Date().addingTimeInterval(-Double(captureManager.elapsedSeconds))
        )
        let state = StudySessionAttributes.ContentState(
            elapsedSeconds: captureManager.elapsedSeconds,
            isPaused: captureManager.isPaused
        )
        do {
            studyActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            print("[LIVE ACTIVITY] Failed to start: \(error)")
        }
    }
    
    private func updateLiveActivity() {
        guard let studyActivity else { return }
        let state = StudySessionAttributes.ContentState(
            elapsedSeconds: captureManager.elapsedSeconds,
            isPaused: captureManager.isPaused
        )
        Task {
            await studyActivity.update(.init(state: state, staleDate: nil))
        }
    }
    
    private func endLiveActivity() {
        guard let studyActivity else { return }
        let finalState = StudySessionAttributes.ContentState(
            elapsedSeconds: captureManager.elapsedSeconds,
            isPaused: false
        )
        Task {
            await studyActivity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.studyActivity = nil
    }
    
    // MARK: - Screen Dimming (visual overlay only)
    
    private func scheduleDim() {
        cancelDimTimer()
        // Only dim if the user enabled it in Settings
        guard autoDimEnabled else { return }
        // Only dim during active recording or timer — never on setup, post, or other screens
        guard phase == .recording || phase == .timerRunning else { return }
        dimTimer = Timer.scheduledTimer(withTimeInterval: dimDelay, repeats: false) { _ in
            Task { @MainActor in
                // Double-check phase hasn't changed while timer was waiting
                guard self.phase == .recording || self.phase == .timerRunning else { return }
                withAnimation(.easeInOut(duration: 1.0)) {
                    self.isDimmed = true
                }
            }
        }
    }
    
    private func wakeScreen() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isDimmed = false
        }
        // Re-schedule dimming after inactivity
        scheduleDim()
    }
    
    private func cancelDimTimer() {
        dimTimer?.invalidate()
        dimTimer = nil
    }
    
    private func restoreBrightness() {
        if isDimmed {
            isDimmed = false
        }
    }
}

// MARK: - Breathing Ring (Continuous Mode)

struct BreathingRing: View {
    let ringColor: Color
    let trackColor: Color
    
    @State private var phase: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(trackColor, lineWidth: 6)
            
            // Animated arc that rotates and pulses
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(ringColor.opacity(0.8), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(phase * 360))
            
            // Second arc offset for visual interest
            Circle()
                .trim(from: 0, to: 0.15)
                .stroke(ringColor.opacity(0.4), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-phase * 360 + 180))
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

// MARK: - Circular Timer Ring

struct CircularTimerRing: View {
    let progress: Double  // 0.0 to 1.0
    let ringColor: Color
    let trackColor: Color
    let lineWidth: CGFloat
    
    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            // Progress
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onDoubleTap: (() -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleTap: onDoubleTap)
    }
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        // Always portrait — the app UI is portrait-locked.
        // Video capture orientation is handled separately on the output connection.
        if let connection = view.previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        
        // UIKit double-tap — reliable on UIViewRepresentable, won't
        // interfere with SwiftUI button taps on overlays above.
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        context.coordinator.onDoubleTap = onDoubleTap
    }
    
    class Coordinator: NSObject {
        var onDoubleTap: (() -> Void)?
        
        init(onDoubleTap: (() -> Void)?) {
            self.onDoubleTap = onDoubleTap
        }
        
        @objc func handleDoubleTap() {
            onDoubleTap?()
        }
    }
    
    class CameraPreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }
    }
}

// MARK: - Unlock Animation: Pigeon Fly

/// The pigeon mascot swoops in, grabs the lock, and flies away
struct UnlockAnim_PigeonFly: View {
    let fg: Color
    let fg2: Color
    
    @State private var pigeonX: CGFloat = -80
    @State private var pigeonY: CGFloat = 20
    @State private var lockOpacity: Double = 1.0
    @State private var lockX: CGFloat = 0
    @State private var lockY: CGFloat = 0
    @State private var showText = false
    
    var body: some View {
        ZStack {
            // Lock that gets carried away
            Image(systemName: "lock.fill")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(fg.opacity(lockOpacity))
                .offset(x: lockX, y: lockY)
            
            // Pigeon (simplified line art)
            Canvas { ctx, size in
                let cx = size.width / 2
                let cy = size.height / 2
                var path = Path()
                // Body
                path.addEllipse(in: CGRect(x: cx - 14, y: cy - 6, width: 28, height: 16))
                // Head
                path.addEllipse(in: CGRect(x: cx - 20, y: cy - 14, width: 14, height: 12))
                // Beak
                path.move(to: CGPoint(x: cx - 22, y: cy - 8))
                path.addLine(to: CGPoint(x: cx - 28, y: cy - 6))
                path.addLine(to: CGPoint(x: cx - 22, y: cy - 4))
                // Wing (flapping)
                path.move(to: CGPoint(x: cx - 4, y: cy - 6))
                path.addLine(to: CGPoint(x: cx, y: cy - 22))
                path.addLine(to: CGPoint(x: cx + 10, y: cy - 6))
                // Top hat
                path.move(to: CGPoint(x: cx - 22, y: cy - 14))
                path.addLine(to: CGPoint(x: cx - 8, y: cy - 14))
                path.addRect(CGRect(x: cx - 20, y: cy - 22, width: 10, height: 8))
                ctx.stroke(path, with: .color(fg), lineWidth: 1.5)
                // Eye
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 16, y: cy - 11, width: 3, height: 3)), with: .color(fg))
            }
            .frame(width: 60, height: 50)
            .offset(x: pigeonX, y: pigeonY)
            
            // "UNLOCKED" text
            if showText {
                Text("UNLOCKED")
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .tracking(4)
                    .foregroundStyle(fg2)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .onAppear {
            // Pigeon flies in from left
            withAnimation(.easeInOut(duration: 0.5)) {
                pigeonX = 0
                pigeonY = 0
            }
            // Pigeon grabs lock and flies out right
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeIn(duration: 0.6)) {
                    pigeonX = 120
                    pigeonY = -40
                    lockX = 120
                    lockY = -40
                    lockOpacity = 0
                }
            }
            // Show text
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showText = true
                }
            }
        }
    }
}

// MARK: - Unlock Animation: Lock Shatter

/// The lock shakes violently then shatters into fragments
struct UnlockAnim_LockShatter: View {
    let fg: Color
    let fg2: Color
    
    @State private var shakeAmount: CGFloat = 0
    @State private var shattered = false
    @State private var fragments: [(x: CGFloat, y: CGFloat, rot: Double, opacity: Double)] = Array(repeating: (0, 0, 0, 1), count: 6)
    @State private var showText = false
    
    var body: some View {
        ZStack {
            if !shattered {
                Image(systemName: "lock.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(fg)
                    .offset(x: shakeAmount)
            } else {
                // Shattered pieces
                ForEach(0..<6, id: \.self) { i in
                    Image(systemName: ["lock.slash", "triangle.fill", "diamond.fill", "square.fill", "circle.fill", "star.fill"][i])
                        .font(.system(size: [12, 8, 7, 9, 6, 8][i]))
                        .foregroundStyle(fg.opacity(fragments[i].opacity))
                        .offset(x: fragments[i].x, y: fragments[i].y)
                        .rotationEffect(.degrees(fragments[i].rot))
                }
            }
            
            if showText {
                Text("UNLOCKED")
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .tracking(4)
                    .foregroundStyle(fg2)
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Shake phase
            let shakeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                shakeAmount = CGFloat.random(in: -6...6)
            }
            
            // Shatter after shaking
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                shakeTimer.invalidate()
                shakeAmount = 0
                Haptics.heavy()
                withAnimation(.none) {
                    shattered = true
                }
                // Fly fragments outward
                let angles: [CGFloat] = [-60, -30, 0, 30, 60, 90]
                withAnimation(.easeOut(duration: 0.7)) {
                    for i in 0..<6 {
                        let rad = angles[i] * .pi / 180
                        let dist: CGFloat = CGFloat.random(in: 50...90)
                        fragments[i] = (
                            x: cos(rad) * dist,
                            y: sin(rad) * dist - 20,
                            rot: Double.random(in: -180...180),
                            opacity: 0
                        )
                    }
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showText = true
                }
            }
        }
    }
}

// MARK: - Unlock Animation: Lock Melt

/// The lock melts downward like it's made of wax
struct UnlockAnim_LockMelt: View {
    let fg: Color
    let fg2: Color
    
    @State private var scaleY: CGFloat = 1.0
    @State private var scaleX: CGFloat = 1.0
    @State private var yOffset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var showText = false
    
    var body: some View {
        ZStack {
            Image(systemName: "lock.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(fg.opacity(opacity))
                .scaleEffect(x: scaleX, y: scaleY, anchor: .bottom)
                .offset(y: yOffset)
            
            if showText {
                Text("UNLOCKED")
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .tracking(4)
                    .foregroundStyle(fg2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear {
            // Phase 1: Wobble slightly
            withAnimation(.easeInOut(duration: 0.3).repeatCount(2, autoreverses: true)) {
                scaleX = 1.1
            }
            // Phase 2: Melt down
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeIn(duration: 0.7)) {
                    scaleY = 0.1
                    scaleX = 1.8
                    yOffset = 20
                    opacity = 0
                }
            }
            // Phase 3: Show text
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showText = true
                }
            }
        }
    }
}

// MARK: - Unlock Animation: Key Turn

/// A key slides in from the side, inserts into the lock, and turns
struct UnlockAnim_KeyTurn: View {
    let fg: Color
    let fg2: Color
    
    @State private var keyX: CGFloat = -80
    @State private var keyRotation: Double = 0
    @State private var lockSymbol = "lock.fill"
    @State private var showText = false
    @State private var lockScale: CGFloat = 1.0
    @State private var lockOpacity: Double = 1.0
    
    var body: some View {
        ZStack {
            // Lock
            Image(systemName: lockSymbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(fg.opacity(lockOpacity))
                .scaleEffect(lockScale)
            
            // Key
            Image(systemName: "key.fill")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(fg)
                .rotationEffect(.degrees(keyRotation))
                .offset(x: keyX, y: 2)
            
            if showText {
                Text("UNLOCKED")
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .tracking(4)
                    .foregroundStyle(fg2)
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Key slides in
            withAnimation(.easeOut(duration: 0.4)) {
                keyX = 4
            }
            // Key turns
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Haptics.medium()
                withAnimation(.easeInOut(duration: 0.4)) {
                    keyRotation = 90
                }
            }
            // Lock opens
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                Haptics.light()
                lockSymbol = "lock.open"
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    lockScale = 1.2
                }
            }
            // Both fade
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation(.easeOut(duration: 0.3)) {
                    lockOpacity = 0
                    keyX = 80
                    showText = true
                }
            }
        }
    }
}

// MARK: - Unlock Animation: Lock Shrink Pop

/// The lock shrinks down to a tiny dot then pops with a burst
struct UnlockAnim_LockShrink: View {
    let fg: Color
    let fg2: Color
    
    @State private var lockScale: CGFloat = 1.0
    @State private var lockOpacity: Double = 1.0
    @State private var popped = false
    @State private var ringScale: CGFloat = 0.3
    @State private var ringOpacity: Double = 1.0
    @State private var showText = false
    
    var body: some View {
        ZStack {
            // Pop ring
            if popped {
                Circle()
                    .stroke(fg.opacity(ringOpacity), lineWidth: 2)
                    .frame(width: 60, height: 60)
                    .scaleEffect(ringScale)
            }
            
            // Lock
            if !popped {
                Image(systemName: "lock.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(fg.opacity(lockOpacity))
                    .scaleEffect(lockScale)
            }
            
            if showText {
                Text("UNLOCKED")
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .tracking(4)
                    .foregroundStyle(fg2)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onAppear {
            // Shrink with slight wobble
            withAnimation(.easeIn(duration: 0.6)) {
                lockScale = 0.1
            }
            // Pop!
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                Haptics.heavy()
                popped = true
                withAnimation(.easeOut(duration: 0.5)) {
                    ringScale = 2.5
                    ringOpacity = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showText = true
                }
            }
        }
    }
}

// MARK: - Unlock Animation: Pigeon Peck

/// A pigeon appears and pecks at the lock until it breaks open
struct UnlockAnim_PigeonPeck: View {
    let fg: Color
    let fg2: Color
    
    @State private var pigeonY: CGFloat = -50
    @State private var peckPhase: Int = 0
    @State private var headDip: CGFloat = 0
    @State private var lockHits: Int = 0
    @State private var lockShake: CGFloat = 0
    @State private var lockOpen = false
    @State private var lockFade: Double = 1.0
    @State private var showText = false
    
    var body: some View {
        ZStack {
            // Lock
            Image(systemName: lockOpen ? "lock.open" : "lock.fill")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(fg.opacity(lockFade))
                .offset(x: lockShake, y: 10)
            
            // Pigeon pecking from above
            Canvas { ctx, size in
                let cx = size.width / 2
                let cy = size.height / 2 + headDip
                var path = Path()
                // Body
                path.addEllipse(in: CGRect(x: cx - 12, y: cy - 5, width: 24, height: 14))
                // Head
                path.addEllipse(in: CGRect(x: cx - 4, y: cy + 5, width: 12, height: 10))
                // Beak (pointing down for pecking)
                path.move(to: CGPoint(x: cx + 2, y: cy + 15))
                path.addLine(to: CGPoint(x: cx + 4, y: cy + 22))
                path.addLine(to: CGPoint(x: cx + 6, y: cy + 15))
                // Wings
                path.move(to: CGPoint(x: cx - 12, y: cy - 2))
                path.addLine(to: CGPoint(x: cx - 20, y: cy - 12))
                path.move(to: CGPoint(x: cx + 12, y: cy - 2))
                path.addLine(to: CGPoint(x: cx + 20, y: cy - 12))
                // Top hat
                path.move(to: CGPoint(x: cx - 6, y: cy - 5))
                path.addLine(to: CGPoint(x: cx + 6, y: cy - 5))
                path.addRect(CGRect(x: cx - 4, y: cy - 12, width: 8, height: 7))
                ctx.stroke(path, with: .color(fg), lineWidth: 1.5)
                // Eye
                ctx.fill(Path(ellipseIn: CGRect(x: cx + 1, y: cy + 8, width: 2.5, height: 2.5)), with: .color(fg))
            }
            .frame(width: 50, height: 50)
            .offset(y: pigeonY)
            
            if showText {
                Text("UNLOCKED")
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .tracking(4)
                    .foregroundStyle(fg2)
                    .offset(y: 40)
                    .transition(.opacity)
            }
        }
        .onAppear {
            // Pigeon drops in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                pigeonY = -30
            }
            // Pecking sequence
            func peck(at delay: Double) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    // Dip head down
                    withAnimation(.easeIn(duration: 0.08)) {
                        headDip = 6
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        Haptics.light()
                        lockShake = CGFloat.random(in: -4...4)
                        withAnimation(.easeOut(duration: 0.08)) {
                            headDip = 0
                            lockShake = 0
                        }
                    }
                }
            }
            peck(at: 0.4)
            peck(at: 0.6)
            peck(at: 0.8)
            
            // Lock breaks open
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                Haptics.success()
                lockOpen = true
                withAnimation(.easeOut(duration: 0.3)) {
                    lockFade = 0.3
                    pigeonY = -60
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showText = true
                }
            }
        }
    }
}
