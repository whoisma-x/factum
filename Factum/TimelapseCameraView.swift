//
//  TimelapseCameraView.swift
//  Factum
//
//  Timelapse recording with Pomodoro, set time, and continuous modes.
//  Supports wide-angle cameras and zoom control.
//

import SwiftUI
import AVFoundation

// MARK: - Camera Phase

enum CameraPhase {
    case timerSetup    // Pick timer mode + settings
    case cameraSetup   // Position camera, adjust zoom/flip
    case recording     // Active recording with timer display
}

// MARK: - Camera View

struct TimelapseCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
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
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness
    private let dimDelay: TimeInterval = 5.0
    
    // Pinch-to-zoom baseline
    @State private var zoomAtGestureStart: CGFloat = 1.0
    
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background for all phases — adapts to color scheme
                FactumTheme.background.ignoresSafeArea()
                
                // Camera preview — only visible during camera setup and recording
                if phase != .timerSetup {
                    CameraPreviewView(session: captureManager.captureSession)
                        .ignoresSafeArea()
                }
                
                // Export overlay
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
                
                // Phase overlays
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
                }
                
                // Dim overlay during recording — tap anywhere to wake
                // Uses a light tint so the camera preview stays visible
                if phase == .recording && isDimmed {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "moon.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white.opacity(0.25))
                                Text("Tap to wake")
                                    .font(FactumTheme.captionFont)
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                            .padding(.top, 80)
                        )
                        .onTapGesture {
                            wakeScreen()
                        }
                }
            }
            .background(FactumTheme.background)
            .simultaneousGesture(
                phase != .timerSetup
                    ? MagnifyGesture()
                        .onChanged { value in
                            captureManager.setZoom(zoomAtGestureStart * value.magnification)
                        }
                        .onEnded { _ in
                            zoomAtGestureStart = captureManager.currentZoomFactor
                        }
                    : nil
            )
            .task {
                await captureManager.requestPermissionAndSetup()
                captureManager.startOrientationDetection()
            }
            .onDisappear {
                cancelDimTimer()
                restoreBrightness()
                UIApplication.shared.isIdleTimerDisabled = false
                // Only cleanup if not actively recording — preserve session if backgrounded
                if !captureManager.isRecording {
                    captureManager.cleanup()
                }
            }
            .onChange(of: phase) { _, newPhase in
                // Prevent auto-lock during recording
                UIApplication.shared.isIdleTimerDisabled = (newPhase == .recording)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                if phase == .recording {
                    captureManager.handleEnterBackground()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if phase == .recording {
                    captureManager.handleEnterForeground()
                    // Restart dim timer when coming back
                    wakeScreen()
                }
            }
            .fullScreenCover(isPresented: $showPostCaption) {
                PostCaptionView(
                    durationSeconds: captureManager.elapsedSeconds,
                    videoURL: exportedVideoURL,
                    thumbnailData: thumbnailData,
                    isLandscape: captureManager.isLandscape
                ) {
                    // Dismiss the post caption sheet, then dismiss the camera
                    showPostCaption = false
                    captureManager.cleanup()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        dismiss()
                    }
                }
            }
            .onChange(of: captureManager.isRecording) { _, newValue in
                // Auto-stop triggered by set time or pomodoro max cycles
                if !newValue && phase == .recording && captureManager.elapsedSeconds > 0 && !showPostCaption && !isExportingAndProceeding {
                    exportAndProceed()
                }
            }
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
            
            Spacer()
            
            // Timer mode selection
            VStack(spacing: 24) {
                Text("Choose Timer")
                    .font(FactumTheme.titleFont)
                    .foregroundStyle(FactumTheme.primaryText)
                
                // Mode cards
                VStack(spacing: 12) {
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
                .padding(.top, 8)
            }
            
            Spacer()
            
            // Next button
            Button {
                // Apply custom time settings
                if captureManager.timerMode == .setTime {
                    captureManager.setTimeDurationMinutes = customHours * 60 + customMinutes
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    phase = .cameraSetup
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
                    savedBrightness = UIScreen.main.brightness
                    captureManager.startRecording()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        phase = .recording
                    }
                    scheduleDim()
                } label: {
                    Text("Start Recording")
                        .font(FactumTheme.subheadlineFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(cameraOverlayBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
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
        VStack {
            // Top bar
            HStack {
                Button {
                    cancelDimTimer()
                    restoreBrightness()
                    captureManager.stopRecording()
                    if captureManager.elapsedSeconds > 5 {
                        exportAndProceed()
                    } else {
                        captureManager.cleanup()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                // Flip camera
                Button {
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
            
            Spacer()
            
            // Bottom controls
            VStack(spacing: 16) {
                // Zoom control
                zoomControl
                
                // Stop button
                Button {
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
    }
    
    // MARK: - Timer Display
    
    @ViewBuilder
    private var timerDisplay: some View {
        VStack(spacing: 8) {
            switch captureManager.timerMode {
            case .continuous:
                Text(formatTime(captureManager.elapsedSeconds))
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                
                Text(captureManager.isRecording ? "Recording" : "Tap to start")
                    .font(FactumTheme.bodyFont)
                    .foregroundStyle(.white.opacity(0.7))
                
            case .pomodoro:
                // Phase indicator
                Text(captureManager.pomodoroPhase.rawValue.uppercased())
                    .font(FactumTheme.font(14, weight: .bold))
                    .foregroundStyle(captureManager.isOnBreak ? .green : .white)
                    .tracking(2)
                
                Text(formatTime(captureManager.pomodoroPhaseSecondsRemaining))
                    .font(.system(size: 52, weight: .light, design: .rounded))
                    .foregroundStyle(captureManager.isOnBreak ? .green : .white)
                    .monospacedDigit()
                
                HStack(spacing: 16) {
                    Label(
                        captureManager.pomodoroMaxCycles > 0
                            ? "\(captureManager.pomodoroCompletedCycles)/\(captureManager.pomodoroMaxCycles) cycles"
                            : "\(captureManager.pomodoroCompletedCycles) cycles",
                        systemImage: "checkmark.circle"
                    )
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(.white.opacity(0.6))
                    
                    Text("Total: \(formatTime(captureManager.elapsedSeconds))")
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(.white.opacity(0.6))
                }
                
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
                Text(formatTime(captureManager.countdownSecondsRemaining))
                    .font(.system(size: 52, weight: .light, design: .rounded))
                    .foregroundStyle(captureManager.countdownSecondsRemaining < 60 ? .orange : .white)
                    .monospacedDigit()
                
                Text("remaining")
                    .font(FactumTheme.captionFont)
                    .foregroundStyle(.white.opacity(0.6))
                
                Text("Total: \(formatTime(captureManager.elapsedSeconds))")
                    .font(FactumTheme.captionFont)
                    .foregroundStyle(.white.opacity(0.6))
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

    // MARK: - Helpers

    private func exportAndProceed() {
        // Prevent double calls from stop button + onChange both firing
        guard !isExportingAndProceeding else { return }
        isExportingAndProceeding = true
        
        cancelDimTimer()
        restoreBrightness()
        Task {
            let url = await captureManager.exportTimelapse()
            guard let url else {
                // Export failed or no frames — go back instead of showing broken post screen
                isExportingAndProceeding = false
                captureManager.cleanup()
                dismiss()
                return
            }
            exportedVideoURL = url
            thumbnailData = captureManager.thumbnailImage?.jpegData(compressionQuality: 0.8)
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
    
    /// Smoothly animates UIScreen brightness over the given duration.
    private func animateBrightness(to target: CGFloat, duration: TimeInterval) {
        let current = UIScreen.main.brightness
        let steps = 20
        let stepDuration = duration / Double(steps)
        let delta = (target - current) / CGFloat(steps)
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                UIScreen.main.brightness = current + delta * CGFloat(i)
            }
        }
    }
    
    private func wakeScreen() {
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
        if isDimmed {
            UIScreen.main.brightness = savedBrightness
            isDimmed = false
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
