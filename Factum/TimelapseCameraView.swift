//
//  TimelapseCameraView.swift
//  Factum
//
//  Timelapse recording with Pomodoro, set time, and continuous modes.
//  Supports wide-angle cameras and zoom control.
//

import SwiftUI
import SwiftData
import AVFoundation
import CallKit

// MARK: - Camera Phase

enum CameraPhase {
    case timerSetup      // Pick timer mode + settings
    case cameraSetup     // Position camera, adjust zoom/flip
    case recording       // Active recording with timer display
    case photoCapture    // Take a photo before timer (photo timer mode)
    case photoConfirm    // Confirm photo, tap "Start Timer"
    case timerRunning    // Timer-only display, no camera preview (photo timer mode)
    case photoAfter      // Take a photo after timer ends
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

    // Screen dimming during recording
    @State private var isDimmed = false
    @State private var dimTimer: Timer?
    @State private var brightnessTimer: Timer?
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness
    private let dimDelay: TimeInterval = 15.0
    
    // Photo timer mode
    @State private var isTakingPhoto = false
    @State private var photoBefore = false
    @State private var photoAfterEnabled = false
    @State private var lockMode = false
    @State private var unlockProgress: CGFloat = 0
    @State private var holdStartDate: Date?
    
    // App-leave counter
    @State private var appLeaveCount: Int = 0
    @State private var wasPhoneCall = false
    private let callObserver = CXCallObserver()
    
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
    
    /// Adaptive background for camera overlay elements:
    /// Light mode — translucent white (matches Start Recording style)
    /// Dark mode — translucent dark
    private var cameraOverlayBg: Color {
        colorScheme == .dark ? Color.black.opacity(0.4) : Color.white.opacity(0.25)
    }
    
    /// Adaptive foreground for non-selected zoom buttons
    private var cameraOverlayBtnBg: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.3)
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
                .task { await setupCamera() }
                .onDisappear { handleDisappear() }
                .onChange(of: phase) { _, newPhase in handlePhaseChange(newPhase) }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in handleResignActive() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in handleBecomeActive() }
                .fullScreenCover(isPresented: $showPostCaption) { postCaptionSheet }
                .onChange(of: captureManager.isRecording) { _, newValue in handleRecordingChange(newValue) }
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
        UIApplication.shared.isIdleTimerDisabled = false
        if !captureManager.isRecording {
            captureManager.cleanup()
        }
    }
    
    private func handlePhaseChange(_ newPhase: CameraPhase) {
        UIApplication.shared.isIdleTimerDisabled = (newPhase == .recording || newPhase == .timerRunning || newPhase == .photoConfirm)
    }
    
    private func handleResignActive() {
        if phase == .recording || phase == .timerRunning {
            // Check if this resign is from a phone call (don't count as leaving)
            wasPhoneCall = callObserver.calls.contains { !$0.hasEnded }
            
            if lockMode {
                // Lock mode — end session when leaving the app
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
            }
        }
    }
    
    private func handleBecomeActive() {
        if phase == .recording || phase == .timerRunning {
            if !wasPhoneCall {
                appLeaveCount += 1
            }
            wasPhoneCall = false
            captureManager.handleEnterForeground()
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
            .background(FactumTheme.background)
            .gesture(magnifyGesture)
    }
    
    @ViewBuilder
    private var cameraZStack: some View {
        ZStack {
            FactumTheme.background.ignoresSafeArea()
            
            if showsCameraPreview {
                CameraPreviewView(session: captureManager.captureSession)
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
            FactumTheme.background.opacity(0.7)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(FactumTheme.primaryText)
                    .scaleEffect(1.5)
                Text("Creating your timelapse...")
                    .font(FactumTheme.subheadlineFont)
                    .foregroundStyle(FactumTheme.primaryText)
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
                        .foregroundStyle(FactumTheme.primaryText)
                        .padding(12)
                        .background(FactumTheme.elevated)
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
                
                Text("Choose Timer")
                    .font(FactumTheme.titleFont)
                    .foregroundStyle(FactumTheme.primaryText)
                
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
                        .font(FactumTheme.font(12, weight: .semibold))
                }
                .foregroundStyle(FactumTheme.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(FactumTheme.cardBackground)
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
                            .font(FactumTheme.smallFont)
                            .foregroundStyle(FactumTheme.tertiaryText)
                        Text(captureManager.currentSubject)
                            .font(FactumTheme.subheadlineFont)
                            .foregroundStyle(FactumTheme.primaryText)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FactumTheme.tertiaryText)
                }
                .padding(FactumTheme.spacing16)
                .background(FactumTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: FactumTheme.cornerField))
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
                    .presentationBackground(FactumTheme.background)
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
                            savedBrightness = UIScreen.main.brightness
                            scheduleDim()
                        }
                    } else {
                        phase = .cameraSetup
                    }
                }
            } label: {
                Text("Next")
                    .font(FactumTheme.subheadlineFont)
                    .foregroundStyle(FactumTheme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(FactumTheme.accent)
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
                    .foregroundStyle(captureManager.timerMode == mode ? FactumTheme.accentText : FactumTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(captureManager.timerMode == mode ? FactumTheme.accent : FactumTheme.elevated)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(FactumTheme.subheadlineFont)
                        .foregroundStyle(FactumTheme.primaryText)
                    
                    Text(modeDescription(mode))
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                }
                
                Spacer()
                
                if captureManager.timerMode == mode {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(FactumTheme.accent)
                }
            }
            .padding(14)
            .background(captureManager.timerMode == mode ? FactumTheme.accent.opacity(0.5) : FactumTheme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        captureManager.timerMode == mode ? FactumTheme.accent : .clear,
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
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                    Spacer()
                    HStack(spacing: 8) {
                        stepButton(systemName: "minus") {
                            captureManager.pomodoroStudyMinutes = max(5, captureManager.pomodoroStudyMinutes - 5)
                        }
                        Text("\(captureManager.pomodoroStudyMinutes) min")
                            .font(FactumTheme.font(16, weight: .semibold))
                            .foregroundStyle(FactumTheme.primaryText)
                            .frame(width: 64)
                        stepButton(systemName: "plus") {
                            captureManager.pomodoroStudyMinutes = min(90, captureManager.pomodoroStudyMinutes + 5)
                        }
                    }
                }
                
                HStack {
                    Text("Break")
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                    Spacer()
                    HStack(spacing: 8) {
                        stepButton(systemName: "minus") {
                            captureManager.pomodoroBreakMinutes = max(1, captureManager.pomodoroBreakMinutes - 1)
                        }
                        Text("\(captureManager.pomodoroBreakMinutes) min")
                            .font(FactumTheme.font(16, weight: .semibold))
                            .foregroundStyle(FactumTheme.primaryText)
                            .frame(width: 64)
                        stepButton(systemName: "plus") {
                            captureManager.pomodoroBreakMinutes = min(30, captureManager.pomodoroBreakMinutes + 1)
                        }
                    }
                }
                
                HStack {
                    Text("Cycles")
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.secondaryText)
                    Spacer()
                    HStack(spacing: 8) {
                        stepButton(systemName: "minus") {
                            captureManager.pomodoroMaxCycles = max(0, captureManager.pomodoroMaxCycles - 1)
                        }
                        Text(captureManager.pomodoroMaxCycles == 0 ? "\u{221E}" : "\(captureManager.pomodoroMaxCycles)")
                            .font(FactumTheme.font(16, weight: .semibold))
                            .foregroundStyle(FactumTheme.primaryText)
                            .frame(width: 64)
                        stepButton(systemName: "plus") {
                            captureManager.pomodoroMaxCycles = min(20, captureManager.pomodoroMaxCycles + 1)
                        }
                    }
                }
            }
            .padding(16)
            .background(FactumTheme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
        case .setTime:
            VStack(spacing: 12) {
                Text("Duration")
                    .font(FactumTheme.bodyFont)
                    .foregroundStyle(FactumTheme.secondaryText)
                
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
                                .font(FactumTheme.font(14, weight: .semibold))
                                .foregroundStyle(isSelected ? FactumTheme.accentText : FactumTheme.primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isSelected ? FactumTheme.accent : FactumTheme.elevated)
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
                        .font(FactumTheme.font(18, weight: .bold))
                        .foregroundStyle(FactumTheme.primaryText)
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
            .background(FactumTheme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(FactumTheme.primaryText)
                .frame(width: 32, height: 32)
                .background(FactumTheme.elevated)
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
                    .font(FactumTheme.font(13, weight: .semibold))
            }
            .foregroundStyle(isOn.wrappedValue ? FactumTheme.accentText : FactumTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isOn.wrappedValue ? FactumTheme.accent : FactumTheme.surfaceBackground)
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
                .font(FactumTheme.font(14, weight: .semibold))
                .foregroundStyle(isSelected ? FactumTheme.accentText : FactumTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? FactumTheme.accent : FactumTheme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? FactumTheme.accent : .clear, lineWidth: 1.5)
                )
        }
    }
    
    // MARK: - Camera Setup Overlay
    
    private var cameraSetupOverlay: some View {
        VStack {
            // Top bar
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        phase = .timerSetup
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(cameraOverlayBg)
                        .clipShape(Circle())
                }
                
                Spacer()
                
                Text("Position Camera")
                    .font(FactumTheme.subheadlineFont)
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
            
            // Hint text + orientation indicator
            VStack(spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Double-tap to flip camera")
                    .font(FactumTheme.captionFont)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)

                // Auto-detected orientation indicator
                orientationIndicator
            }
            
            Spacer()
            
            // Bottom controls
            VStack(spacing: 16) {
                // Zoom control
                zoomControl
                
                // Timer mode summary
                timerModeSummary
                
                // Start recording button
                Button {
                    Haptics.medium()
                    savedBrightness = UIScreen.main.brightness
                    // Flash feedback
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
                    Text("Start Recording")
                        .font(FactumTheme.font(18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            Haptics.light()
            captureManager.flipCamera()
            zoomAtGestureStart = captureManager.currentZoomFactor
        }
    }
    
    // MARK: - Timer Mode Summary
    
    private var timerModeSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: captureManager.timerMode.icon)
                .font(.system(size: 14))
                .foregroundStyle(.white)
            
            Text(timerSummaryText)
                .font(FactumTheme.captionFont)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(cameraOverlayBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                    }
                    
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
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Spacer()
                
                // Timer display
                timerDisplay
                
                // Subject pill — tap to switch
                if !lockMode {
                    subjectPill(isCamera: true)
                        .padding(.top, 8)
                }
                
                // Lock toggle — below the timer
                lockButton
                    .padding(.top, 12)
                
                // App leave counter
                if appLeaveCount > 0 {
                    leaveCounter(isCamera: true)
                        .padding(.top, 8)
                }
                
                Spacer()
                
                // Bottom controls
                VStack(spacing: 16) {
                    // Zoom control
                    zoomControl
                    
                    // Stop button
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
                                .frame(width: 80, height: 80)
                            
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.red)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .disabled(captureManager.isExporting)
                    .padding(.bottom, 40)
                }
            }
            .opacity(captureManager.isExporting ? 0.3 : 1.0)
            .allowsHitTesting(!captureManager.isExporting)
            
            // Paused overlay
            if captureManager.isPaused {
                pausedOverlay(isCamera: true)
            }
            
            // Screen lock overlay (covers everything when lock mode is active)
            if lockMode && !captureManager.isPaused {
                screenLockOverlay(isCamera: true)
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
        VStack(spacing: 8) {
            switch captureManager.timerMode {
            case .continuous:
                ZStack {
                    BreathingRing(ringColor: .white, trackColor: .white.opacity(0.15))
                        .frame(width: 220, height: 220)
                    
                    VStack(spacing: 4) {
                        Text(formatTime(captureManager.elapsedSeconds))
                            .font(.system(size: 42, weight: .light, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        
                        Text(captureManager.isRecording ? "Recording" : "Tap to start")
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                
            case .pomodoro:
                // Phase indicator
                Text(captureManager.pomodoroPhase.rawValue.uppercased())
                    .font(FactumTheme.font(14, weight: .bold))
                    .foregroundStyle(captureManager.isOnBreak ? .green : .white)
                    .tracking(2)
                
                // Circular progress with cycle time
                ZStack {
                    CircularTimerRing(
                        progress: pomodoroPhaseProgress,
                        ringColor: captureManager.isOnBreak ? .green : .white,
                        trackColor: .white.opacity(0.15),
                        lineWidth: 6
                    )
                    .frame(width: 220, height: 220)
                    
                    VStack(spacing: 4) {
                        Text(formatTime(captureManager.pomodoroPhaseSecondsRemaining))
                            .font(.system(size: 40, weight: .light, design: .rounded))
                            .foregroundStyle(captureManager.isOnBreak ? .green : .white)
                            .monospacedDigit()
                        
                        Text(
                            captureManager.pomodoroMaxCycles > 0
                                ? "\(captureManager.pomodoroCompletedCycles)/\(captureManager.pomodoroMaxCycles) cycles"
                                : "\(captureManager.pomodoroCompletedCycles) cycles"
                        )
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                
                Text(formatTime(captureManager.elapsedSeconds))
                    .font(FactumTheme.font(16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
                    .padding(.top, 4)
                
                if captureManager.isOnBreak {
                    Text("Take a break! Recording paused.")
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(.green.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.green.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
            case .setTime:
                // Circular progress with countdown
                ZStack {
                    CircularTimerRing(
                        progress: setTimeProgress,
                        ringColor: captureManager.countdownSecondsRemaining < 60 ? .orange : .white,
                        trackColor: .white.opacity(0.15),
                        lineWidth: 6
                    )
                    .frame(width: 220, height: 220)
                    
                    VStack(spacing: 4) {
                        Text(formatTime(captureManager.countdownSecondsRemaining))
                            .font(.system(size: 40, weight: .light, design: .rounded))
                            .foregroundStyle(captureManager.countdownSecondsRemaining < 60 ? .orange : .white)
                            .monospacedDigit()
                        
                        Text("remaining")
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                
                Text(formatTime(captureManager.elapsedSeconds))
                    .font(FactumTheme.font(16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
                    .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Zoom Control
    
    private var zoomControl: some View {
        HStack(spacing: 10) {
            // Only include 0.5x if the device actually has an ultra-wide lens
            let allLevels: [(String, CGFloat)] = [
                ("0.5×", 0.5),
                ("1×", 1.0),
                ("2×", 2.0),
                ("5×", 5.0)
            ]
            let zoomLevels = allLevels.filter { _, factor in
                if factor < 1.0 { return captureManager.hasUltraWide }
                return factor <= captureManager.maxZoomFactor
            }
            
            ForEach(zoomLevels, id: \.0) { label, factor in
                let isAvailable = factor >= captureManager.minZoomFactor && factor <= captureManager.maxZoomFactor
                let isClosest = closestZoomLevel(from: zoomLevels) == factor
                
                Button {
                    captureManager.setZoom(factor, animated: true)
                    zoomAtGestureStart = factor
                } label: {
                    Text(isClosest && abs(captureManager.currentZoomFactor - factor) > 0.05
                         ? formatZoomLabel(captureManager.currentZoomFactor)
                         : label)
                        .font(FactumTheme.font(12, weight: isClosest ? .bold : .medium))
                        .foregroundStyle(isClosest ? .black : .white.opacity(isAvailable ? 0.8 : 0.3))
                        .frame(width: 44, height: 44)
                        .background(isClosest ? .yellow : cameraOverlayBtnBg)
                        .clipShape(Circle())
                }
                .disabled(!isAvailable)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(cameraOverlayBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    /// Finds which zoom level button is closest to the current zoom factor
    private func closestZoomLevel(from levels: [(String, CGFloat)]) -> CGFloat {
        let current = captureManager.currentZoomFactor
        return levels.min(by: {
            abs(log2($0.1) - log2(current)) < abs(log2($1.1) - log2(current))
        })?.1 ?? 1.0
    }
    
    /// Format zoom label like "1.5×" for intermediate values
    private func formatZoomLabel(_ factor: CGFloat) -> String {
        if abs(factor - factor.rounded()) < 0.05 {
            return "\(Int(factor.rounded()))×"
        }
        return String(format: "%.1f×", factor)
    }
    
    // MARK: - Orientation Indicator

    /// Passive indicator showing the auto-detected device orientation.
    private var orientationIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: captureManager.detectedOrientation.icon)
                .font(.system(size: 12))
            Text(captureManager.detectedOrientation.displayLabel)
                .font(FactumTheme.font(12, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(cameraOverlayBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    .font(FactumTheme.subheadlineFont)
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
                // Zoom control
                zoomControl
                
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
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            Haptics.light()
            captureManager.flipCamera()
            zoomAtGestureStart = captureManager.currentZoomFactor
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
                            .font(FactumTheme.font(14, weight: .semibold))
                    }
                    .foregroundStyle(FactumTheme.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(FactumTheme.elevated)
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
                    .font(FactumTheme.font(18, weight: .semibold))
                    .foregroundStyle(FactumTheme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(FactumTheme.accent)
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
                                .foregroundStyle(FactumTheme.primaryText)
                                .padding(12)
                                .background(FactumTheme.elevated)
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
                                .strokeBorder(FactumTheme.accent, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        .padding(.bottom, 12)
                }
                
                // Timer display — themed for non-camera background
                photoTimerDisplay
                
                // Subject pill — tap to switch
                if !lockMode {
                    subjectPill(isCamera: false)
                        .padding(.top, 8)
                }
                
                // Lock toggle — below the timer
                lockButton
                    .padding(.top, 12)
                
                // App leave counter
                if appLeaveCount > 0 {
                    leaveCounter(isCamera: false)
                        .padding(.top, 8)
                }
                
                Spacer()
                
                // End Session button
                Button {
                    Haptics.medium()
                    cancelDimTimer()
                    restoreBrightness()
                    captureManager.stopRecording()
                    handleTimerEnd()
                } label: {
                    Text("End Session")
                        .font(FactumTheme.font(18, weight: .semibold))
                        .foregroundStyle(FactumTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(FactumTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
            
            // Paused overlay
            if captureManager.isPaused {
                pausedOverlay(isCamera: false)
            }
            
            // Screen lock overlay (covers everything when lock mode is active)
            if lockMode && !captureManager.isPaused {
                screenLockOverlay(isCamera: false)
            }
        }
    }
    
    // MARK: - Photo Timer Display
    
    @ViewBuilder
    private var photoTimerDisplay: some View {
        VStack(spacing: 8) {
            switch captureManager.timerMode {
            case .continuous:
                ZStack {
                    BreathingRing(ringColor: FactumTheme.accent, trackColor: FactumTheme.elevated)
                        .frame(width: 220, height: 220)
                    
                    VStack(spacing: 4) {
                        Text(formatTime(captureManager.elapsedSeconds))
                            .font(.system(size: 42, weight: .light, design: .rounded))
                            .foregroundStyle(FactumTheme.primaryText)
                            .monospacedDigit()
                        
                        Text("Studying")
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.secondaryText)
                    }
                }
                
            case .pomodoro:
                Text(captureManager.pomodoroPhase.rawValue.uppercased())
                    .font(FactumTheme.font(14, weight: .bold))
                    .foregroundStyle(captureManager.isOnBreak ? .green : FactumTheme.primaryText)
                    .tracking(2)
                
                ZStack {
                    CircularTimerRing(
                        progress: pomodoroPhaseProgress,
                        ringColor: captureManager.isOnBreak ? .green : FactumTheme.accent,
                        trackColor: FactumTheme.elevated,
                        lineWidth: 6
                    )
                    .frame(width: 220, height: 220)
                    
                    VStack(spacing: 4) {
                        Text(formatTime(captureManager.pomodoroPhaseSecondsRemaining))
                            .font(.system(size: 40, weight: .light, design: .rounded))
                            .foregroundStyle(captureManager.isOnBreak ? .green : FactumTheme.primaryText)
                            .monospacedDigit()
                        
                        Text(
                            captureManager.pomodoroMaxCycles > 0
                                ? "\(captureManager.pomodoroCompletedCycles)/\(captureManager.pomodoroMaxCycles) cycles"
                                : "\(captureManager.pomodoroCompletedCycles) cycles"
                        )
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.secondaryText)
                    }
                }
                
                Text(formatTime(captureManager.elapsedSeconds))
                    .font(FactumTheme.font(16, weight: .medium))
                    .foregroundStyle(FactumTheme.secondaryText)
                    .monospacedDigit()
                    .padding(.top, 4)
                
                if captureManager.isOnBreak {
                    Text("Take a break!")
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(.green.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.green.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
            case .setTime:
                ZStack {
                    CircularTimerRing(
                        progress: setTimeProgress,
                        ringColor: captureManager.countdownSecondsRemaining < 60 ? .orange : FactumTheme.accent,
                        trackColor: FactumTheme.elevated,
                        lineWidth: 6
                    )
                    .frame(width: 220, height: 220)
                    
                    VStack(spacing: 4) {
                        Text(formatTime(captureManager.countdownSecondsRemaining))
                            .font(.system(size: 40, weight: .light, design: .rounded))
                            .foregroundStyle(captureManager.countdownSecondsRemaining < 60 ? .orange : FactumTheme.primaryText)
                            .monospacedDigit()
                        
                        Text("remaining")
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.secondaryText)
                    }
                }
                
                Text(formatTime(captureManager.elapsedSeconds))
                    .font(FactumTheme.font(16, weight: .medium))
                    .foregroundStyle(FactumTheme.secondaryText)
                    .monospacedDigit()
                    .padding(.top, 4)
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
        savedBrightness = UIScreen.main.brightness
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
                    .font(FactumTheme.font(13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(isCamera ? .white : FactumTheme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isCamera ? Color.black.opacity(0.4) : FactumTheme.elevated)
            .clipShape(Capsule())
        }
        .sheet(isPresented: $showSubjectPicker) {
            subjectSwitchSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(FactumTheme.background)
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
                                    .font(FactumTheme.bodyFont)
                                    .foregroundStyle(FactumTheme.primaryText)
                                Spacer()
                                if captureManager.currentSubject == studySubject.name {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(FactumTheme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                captureManager.currentSubject == studySubject.name
                                ? studySubject.color.opacity(0.15)
                                : FactumTheme.cardBackground
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
                        .font(FactumTheme.headlineFont)
                        .foregroundStyle(FactumTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSubjectPicker = false }
                        .foregroundStyle(FactumTheme.accent)
                }
            }
            .toolbarBackground(FactumTheme.background, for: .navigationBar)
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
                                    .font(FactumTheme.bodyFont)
                                    .foregroundStyle(FactumTheme.primaryText)
                                Spacer()
                                if captureManager.currentSubject == studySubject.name {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(FactumTheme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                captureManager.currentSubject == studySubject.name
                                ? studySubject.color.opacity(0.15)
                                : FactumTheme.cardBackground
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
                                .foregroundStyle(FactumTheme.accent)
                            Text("New Subject")
                                .font(FactumTheme.bodyFont)
                                .foregroundStyle(FactumTheme.accent)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(FactumTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(FactumTheme.separator, lineWidth: 1)
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
                        .font(FactumTheme.headlineFont)
                        .foregroundStyle(FactumTheme.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSetupSubjectPicker = false }
                        .foregroundStyle(FactumTheme.accent)
                }
            }
            .toolbarBackground(FactumTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    // MARK: - Lock Button
    
    private var lockButton: some View {
        let isOnCamera = phase == .recording
        let fgOn: Color = isOnCamera ? .white : FactumTheme.accentText
        let fgOff: Color = isOnCamera ? .white.opacity(0.8) : FactumTheme.secondaryText
        let bgOn: Color = isOnCamera ? .white.opacity(0.3) : FactumTheme.accent
        let bgOff: Color = isOnCamera ? .black.opacity(0.4) : FactumTheme.elevated
        
        return Button {
            Haptics.light()
            withAnimation(.easeInOut(duration: 0.2)) {
                lockMode.toggle()
            }
        } label: {
            Image(systemName: lockMode ? "lock.fill" : "lock.open")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(lockMode ? fgOn : fgOff)
                .padding(12)
                .background(lockMode ? bgOn : bgOff)
                .clipShape(Circle())
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
            Text("Ends your session and saves your progress when you leave the app. Also hides the pause button so you can't accidentally interrupt your session.")
        }
    }
    
    // MARK: - Screen Lock Overlay
    
    private func screenLockOverlay(isCamera: Bool) -> some View {
        ZStack {
            (isCamera ? Color.black.opacity(0.85) : FactumTheme.background.opacity(0.95))
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(isCamera ? .white.opacity(0.6) : FactumTheme.secondaryText.opacity(0.6))
                
                Text("Screen Locked")
                    .font(FactumTheme.font(20, weight: .semibold))
                    .foregroundStyle(isCamera ? .white.opacity(0.8) : FactumTheme.primaryText)
                
                // Timer still visible
                Text(formatTime(captureManager.elapsedSeconds))
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .foregroundStyle(isCamera ? .white : FactumTheme.primaryText)
                
                // Pomodoro phase indicator
                if captureManager.timerMode == .pomodoro {
                    Text(captureManager.isOnBreak ? "Break" : "Focus")
                        .font(FactumTheme.font(16, weight: .medium))
                        .foregroundStyle(captureManager.isOnBreak ? .green : (isCamera ? .white.opacity(0.6) : FactumTheme.secondaryText))
                }
                
                // App leave counter on lock screen
                if appLeaveCount > 0 {
                    leaveCounter(isCamera: isCamera)
                        .padding(.top, 8)
                }
                
                Text("Hold to unlock")
                    .font(FactumTheme.captionFont)
                    .foregroundStyle(isCamera ? .white.opacity(0.4) : FactumTheme.tertiaryText)
                    .padding(.top, 12)
                
                // Hold-to-unlock button with progress ring
                ZStack {
                    // Progress ring
                    Circle()
                        .stroke(isCamera ? .white.opacity(0.1) : FactumTheme.elevated, lineWidth: 3)
                        .frame(width: 64, height: 64)
                    
                    Circle()
                        .trim(from: 0, to: unlockProgress)
                        .stroke(
                            isCamera ? Color.white : FactumTheme.accent,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                    
                    Image(systemName: unlockProgress >= 1.0 ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isCamera ? .white.opacity(0.7) : FactumTheme.secondaryText)
                        .contentTransition(.symbolEffect(.replace))
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if holdStartDate == nil {
                                holdStartDate = Date()
                                Haptics.light()
                                withAnimation(.linear(duration: 2.0)) {
                                    unlockProgress = 1.0
                                }
                            }
                        }
                        .onEnded { _ in
                            if let start = holdStartDate, Date().timeIntervalSince(start) >= 2.0 {
                                // Held long enough — unlock
                                Haptics.success()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    lockMode = false
                                }
                                unlockProgress = 0
                            } else {
                                // Released early — reset
                                withAnimation(.easeOut(duration: 0.3)) {
                                    unlockProgress = 0
                                }
                            }
                            holdStartDate = nil
                        }
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { } // Eat all taps
    }
    
    // MARK: - Leave Counter
    
    private func leaveCounter(isCamera: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 12, weight: .semibold))
            Text("Left app \(appLeaveCount) \(appLeaveCount == 1 ? "time" : "times")")
                .font(FactumTheme.font(12, weight: .medium))
        }
        .foregroundStyle(isCamera ? .white.opacity(0.5) : FactumTheme.tertiaryText)
    }
    
    // MARK: - Paused Overlay
    
    private func pausedOverlay(isCamera: Bool) -> some View {
        ZStack {
            // Dim background
            (isCamera ? Color.black.opacity(0.7) : FactumTheme.background.opacity(0.9))
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Paused label
                VStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(isCamera ? .white : FactumTheme.primaryText)
                    
                    Text("Paused")
                        .font(FactumTheme.font(28, weight: .bold))
                        .foregroundStyle(isCamera ? .white : FactumTheme.primaryText)
                    
                    Text(formatTime(captureManager.elapsedSeconds))
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(isCamera ? .white.opacity(0.6) : FactumTheme.secondaryText)
                        .monospacedDigit()
                }
                
                // Resume button
                Button {
                    Haptics.medium()
                    captureManager.resumeRecording()
                    scheduleDim()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Resume")
                    }
                    .font(FactumTheme.font(18, weight: .semibold))
                    .foregroundStyle(isCamera ? .black : FactumTheme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(isCamera ? .white : FactumTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 40)
                
                // End Session button
                Button {
                    Haptics.medium()
                    // Keep paused (don't stop) so Back can return to paused overlay
                    if phase == .timerRunning {
                        handleTimerEnd()
                    } else {
                        exportAndProceed()
                    }
                } label: {
                    Text("End Session")
                        .font(FactumTheme.font(16, weight: .medium))
                        .foregroundStyle(isCamera ? .white.opacity(0.7) : FactumTheme.secondaryText)
                }
                .padding(.top, 4)
                
                // Discard button
                Button {
                    Haptics.warning()
                    showDiscardConfirm = true
                } label: {
                    Text("Discard")
                        .font(FactumTheme.font(14, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .padding(.top, 8)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: captureManager.isPaused)
        .alert("Discard Session?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) {
                captureManager.stopRecording()
                captureManager.cleanup()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your study time and recording will be lost.")
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
    
    // MARK: - Screen Dimming
    
    /// The dimmed brightness level — low enough to save battery but
    /// bright enough that the camera feed is still visible.
    private let dimmedBrightness: CGFloat = 0.05
    
    private func scheduleDim() {
        cancelDimTimer()
        dimTimer = Timer.scheduledTimer(withTimeInterval: dimDelay, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 1.0)) {
                    isDimmed = true
                }
                savedBrightness = UIScreen.main.brightness
                // Gradually lower brightness instead of snapping to black
                animateBrightness(to: dimmedBrightness, duration: 1.0)
            }
        }
    }
    
    /// Smoothly animates UIScreen brightness over the given duration using a cancellable timer.
    private func animateBrightness(to target: CGFloat, duration: TimeInterval) {
        brightnessTimer?.invalidate()
        let current = UIScreen.main.brightness
        let steps = 20
        let stepDuration = duration / Double(steps)
        let delta = (target - current) / CGFloat(steps)
        var step = 0
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { timer in
            step += 1
            UIScreen.main.brightness = current + delta * CGFloat(step)
            if step >= steps { timer.invalidate() }
        }
    }
    
    private func wakeScreen() {
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            isDimmed = false
        }
        animateBrightness(to: savedBrightness, duration: 0.3)
        // Re-schedule dimming after inactivity
        scheduleDim()
    }
    
    private func cancelDimTimer() {
        dimTimer?.invalidate()
        dimTimer = nil
    }
    
    private func restoreBrightness() {
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        if isDimmed {
            UIScreen.main.brightness = savedBrightness
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
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Preview stays at portrait rotation; nothing to update.
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
