//
//  TutorialOverlayView.swift
//  Pigeon
//
//  Post-onboarding coach marks tutorial
//

import SwiftUI

// MARK: - Tutorial Steps (tab bar + profile)

enum TutorialStep: Int, CaseIterable {
    case feedTab = 0
    case recordButton = 1
    // Steps 2-3 happen inside the camera (CameraTutorialStep)
    case profileTab = 2
    case stats = 3
    
    var title: String {
        switch self {
        case .feedTab:      return "Your Feed"
        case .recordButton: return "Record"
        case .profileTab:   return "Profile"
        case .stats:        return "Detailed Stats"
        }
    }
    
    var description: String {
        switch self {
        case .feedTab:      return "Your sessions show up here as posts."
        case .recordButton: return "Timelapse, pomodoro, or timer."
        case .profileTab:   return "Your stats, streaks, and settings."
        case .stats:        return "Weekly, monthly, and yearly breakdowns."
        }
    }
    
    var icon: String {
        switch self {
        case .feedTab:      return "house.fill"
        case .recordButton: return "video.fill"
        case .profileTab:   return "person.circle.fill"
        case .stats:        return "chart.bar.fill"
        }
    }
    
    var buttonLabel: String {
        self == .stats ? "Got it" : "Next"
    }
    
    var isLast: Bool {
        self == .stats
    }
    
    /// Whether this step highlights a tab bar item with a spotlight cutout
    var hasTabSpotlight: Bool {
        switch self {
        case .feedTab, .recordButton, .profileTab: return true
        case .stats: return false
        }
    }
    
    /// Whether the arrow points at a custom target rect (e.g. stats card) instead of tab bar
    var pointsAtCustomTarget: Bool {
        self == .stats
    }
    
    /// Which tab index the spotlight / arrow points at (tab bar steps only)
    var arrowTabIndex: Int {
        switch self {
        case .feedTab:      return 0
        case .recordButton: return 2
        case .profileTab:   return 4
        case .stats:        return 4
        }
    }
    
    /// Tab index to switch to when this step becomes active
    var targetTab: Int? {
        switch self {
        case .feedTab:      return 0
        case .recordButton: return nil
        case .profileTab:   return 4
        case .stats:        return nil
        }
    }
    
    /// Whether advancing past this step opens the camera for in-camera tutorial
    var opensCamera: Bool {
        self == .recordButton
    }
}

// MARK: - Camera Tutorial Steps (shown inside TimelapseCameraView)

enum CameraTutorialStep: Int, CaseIterable {
    case subjects = 0
    case lockMode = 1
    
    var title: String {
        switch self {
        case .subjects: return "Study Subjects"
        case .lockMode: return "Lock Mode"
        }
    }
    
    var description: String {
        switch self {
        case .subjects: return "Pick a subject before you start recording."
        case .lockMode: return "Auto-saves when you leave the app and hides pause."
        }
    }
    
    var icon: String {
        switch self {
        case .subjects: return "book.fill"
        case .lockMode: return "lock.fill"
        }
    }
    
    var isLast: Bool { self == .lockMode }
}

/// Preference key for reporting the subject picker frame from TimelapseCameraView.
struct SubjectPickerFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Spotlight Overlay (dimmed background with cutout)

struct SpotlightOverlay: View {
    let targetRect: CGRect
    let cornerRadius: CGFloat = 14
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geo.size))
                path.addRoundedRect(
                    in: targetRect.insetBy(dx: -6, dy: -6),
                    cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
                )
            }
            .fill(style: FillStyle(eoFill: true))
            .foregroundStyle(Color.black.opacity(0.65))
        }
        .ignoresSafeArea()
    }
}

// MARK: - Arrow Shape

/// A small downward-pointing triangle used to connect the tooltip card to the spotlight.
struct TooltipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX - 8, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX + 8, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - Tutorial Overlay View

/// Preference key for reporting the stats card frame from ProfileView.
struct StatsCardFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct TutorialOverlayView: View {
    @Binding var isShowing: Bool
    @Binding var selectedTab: Int
    @Binding var showCameraTutorial: Bool
    /// The actual tab bar frame in global coordinates, passed from ContentView.
    let tabBarFrame: CGRect
    /// The "View Detailed Stats" card frame in global coordinates, passed from ProfileView.
    let statsCardFrame: CGRect
    @State private var currentStep: TutorialStep = .feedTab
    @State private var animateIn = false
    
    var body: some View {
        GeometryReader { geometry in
            let spotlight = spotlightRect(for: currentStep)
            
            ZStack {
                // Background overlay with spotlight cutout
                if spotlight != .zero {
                    SpotlightOverlay(targetRect: spotlight)
                        .transition(.opacity)
                } else {
                    Color.black.opacity(0.65)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
                
                // Tooltip card with arrow
                tooltipWithArrow(in: geometry, spotlightRect: spotlight)
                    .id(currentStep)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .opacity(animateIn ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    animateIn = true
                }
            }
            // When camera tutorial finishes, resume at profile step
            .onChange(of: showCameraTutorial) { _, isCameraShowing in
                if !isCameraShowing && currentStep == .recordButton {
                    selectedTab = 4
                    currentStep = .profileTab
                    // Delay to let the full-screen cover dismiss
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            animateIn = true
                        }
                    }
                }
            }
            // Block taps from reaching content below
            .contentShape(Rectangle())
            .onTapGesture { }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Spotlight Position Calculation
    
    /// Returns the center point of a tab icon in global coordinates.
    private func tabCenter(for tabIndex: Int) -> CGPoint {
        let innerHPad: CGFloat = 8
        let innerVPad: CGFloat = 6
        let buttonHeight: CGFloat = 48
        
        let contentLeft = tabBarFrame.minX + innerHPad
        let contentWidth = tabBarFrame.width - innerHPad * 2
        let tabWidth = contentWidth / 5.0
        
        let cx = contentLeft + tabWidth * CGFloat(tabIndex) + tabWidth / 2
        let cy = tabBarFrame.minY + innerVPad + buttonHeight / 2
        return CGPoint(x: cx, y: cy)
    }
    
    private func spotlightRect(for step: TutorialStep) -> CGRect {
        if step.hasTabSpotlight {
            let center = tabCenter(for: step.arrowTabIndex)
            let innerHPad: CGFloat = 8
            let contentWidth = tabBarFrame.width - innerHPad * 2
            let tabWidth = contentWidth / 5.0
            let spotWidth = tabWidth - 4
            let spotHeight: CGFloat = 48
            return CGRect(
                x: center.x - spotWidth / 2,
                y: center.y - spotHeight / 2,
                width: spotWidth,
                height: spotHeight
            )
        } else if step.pointsAtCustomTarget && statsCardFrame != .zero {
            return statsCardFrame
        }
        return .zero
    }
    
    // MARK: - Tooltip with Arrow
    
    private func tooltipWithArrow(in geometry: GeometryProxy, spotlightRect: CGRect) -> some View {
        let screenWidth = geometry.size.width
        
        if currentStep.pointsAtCustomTarget && statsCardFrame != .zero {
            // Stats step: tooltip appears below the stats card, arrow points UP
            let arrowCenterX = statsCardFrame.midX
            let topPad = statsCardFrame.maxY + 18  // 12pt gap below spotlight + 6pt inset
            
            return AnyView(
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        // Arrow pointing up at the stats card
                        TooltipArrow()
                            .fill(PigeonTheme.cardBackground)
                            .frame(width: 16, height: 10)
                            .rotationEffect(.degrees(180))
                            .offset(x: arrowCenterX - screenWidth / 2)
                        
                        cardContent
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                }
                .padding(.top, topPad)
            )
        } else {
            // Tab bar steps: tooltip above the tab bar, arrow points DOWN
            let screenHeight = geometry.size.height
            let targetCenter = tabCenter(for: currentStep.arrowTabIndex)
            let arrowCenterX = targetCenter.x
            let anchorY: CGFloat = currentStep.hasTabSpotlight
                ? spotlightRect.minY - 12
                : tabBarFrame.minY - 12
            let bottomPad = max(0, screenHeight - anchorY)
            
            return AnyView(
                VStack(spacing: 0) {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        cardContent
                        
                        // Arrow pointing down at the target tab
                        TooltipArrow()
                            .fill(PigeonTheme.cardBackground)
                            .frame(width: 16, height: 10)
                            .offset(x: arrowCenterX - screenWidth / 2)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, bottomPad)
            )
        }
    }
    
    // MARK: - Card Content
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Icon + title row
            HStack(spacing: 10) {
                Image(systemName: currentStep.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(PigeonTheme.secondaryText)
                
                Text(currentStep.title)
                    .font(PigeonTheme.headlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
            }
            
            Text(currentStep.description)
                .font(PigeonTheme.font(16, weight: .light))
                .foregroundStyle(PigeonTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                // Step indicator dots (6 total: 2 tab + 2 camera + 2 tab)
                HStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { i in
                        let isActive: Bool = {
                            switch i {
                            case 0: return currentStep == .feedTab
                            case 1: return currentStep == .recordButton
                            // 2, 3 are camera steps — never active here
                            case 4: return currentStep == .profileTab
                            case 5: return currentStep == .stats
                            default: return false
                            }
                        }()
                        Circle()
                            .fill(isActive ? PigeonTheme.primaryText : PigeonTheme.separator)
                            .frame(width: 6, height: 6)
                    }
                }
                
                Spacer()
                
                // Skip button (except on last step)
                if !currentStep.isLast {
                    Button("Skip") {
                        Haptics.light()
                        dismissTutorial()
                    }
                    .font(PigeonTheme.captionFont)
                    .foregroundStyle(PigeonTheme.tertiaryText)
                    .padding(.trailing, 8)
                }
                
                // Next / Got it button
                Button(currentStep.buttonLabel) {
                    Haptics.light()
                    advanceStep()
                }
                .buttonStyle(PigeonButtonStyle())
            }
            .padding(.top, 2)
        }
        .padding(20)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 4)
    }
    
    // MARK: - Step Navigation
    
    private func advanceStep() {
        // After record step, open the camera for in-camera tutorial
        if currentStep.opensCamera {
            withAnimation(.easeOut(duration: 0.2)) {
                animateIn = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                showCameraTutorial = true
            }
            return
        }
        
        guard let next = TutorialStep(rawValue: currentStep.rawValue + 1) else {
            dismissTutorial()
            return
        }
        
        // Switch tab if needed
        if let tab = next.targetTab {
            selectedTab = tab
        }
        
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = next
        }
    }
    
    private func dismissTutorial() {
        withAnimation(.easeOut(duration: 0.3)) {
            animateIn = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isShowing = false
        }
    }
}
// MARK: - Camera Tutorial Overlay (shown inside TimelapseCameraView)

struct CameraTutorialOverlay: View {
    @Binding var isShowing: Bool
    let onFinished: () -> Void
    /// The subject picker card frame in global coordinates.
    let subjectPickerFrame: CGRect
    @State private var currentStep: CameraTutorialStep = .subjects
    @State private var animateIn = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Spotlight on the subject picker for step 1, dimmed for step 2
                if currentStep == .subjects && subjectPickerFrame != .zero {
                    SpotlightOverlay(targetRect: subjectPickerFrame)
                        .transition(.opacity)
                } else {
                    Color.black.opacity(0.65)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
                
                // Tooltip card
                cameraTooltip(in: geometry)
                    .id(currentStep)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .opacity(animateIn ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    animateIn = true
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { }
        }
        .ignoresSafeArea()
    }
    
    private func cameraTooltip(in geometry: GeometryProxy) -> some View {
        let screenWidth = geometry.size.width
        
        if currentStep == .subjects && subjectPickerFrame != .zero {
            // Position tooltip above the subject picker, arrow points down at it
            let screenHeight = geometry.size.height
            let arrowCenterX = subjectPickerFrame.midX
            let anchorY = subjectPickerFrame.minY - 12
            let bottomPad = max(0, screenHeight - anchorY)
            
            return AnyView(
                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 0) {
                        cameraCardContent
                        TooltipArrow()
                            .fill(PigeonTheme.cardBackground)
                            .frame(width: 16, height: 10)
                            .offset(x: arrowCenterX - screenWidth / 2)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, bottomPad)
            )
        } else {
            // Lock mode — centered card, no arrow
            return AnyView(
                VStack {
                    Spacer()
                    cameraCardContent
                        .padding(.horizontal, 24)
                    Spacer()
                }
            )
        }
    }
    
    private var cameraCardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: currentStep.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(PigeonTheme.secondaryText)
                
                Text(currentStep.title)
                    .font(PigeonTheme.headlineFont)
                    .foregroundStyle(PigeonTheme.primaryText)
            }
            
            Text(currentStep.description)
                .font(PigeonTheme.font(16, weight: .light))
                .foregroundStyle(PigeonTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                // Step indicator dots (6 total, steps 2-3 are camera)
                HStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { i in
                        let isActive: Bool = {
                            switch i {
                            case 2: return currentStep == .subjects
                            case 3: return currentStep == .lockMode
                            default: return false
                            }
                        }()
                        Circle()
                            .fill(isActive ? PigeonTheme.primaryText : PigeonTheme.separator)
                            .frame(width: 6, height: 6)
                    }
                }
                
                Spacer()
                
                Button("Skip") {
                    Haptics.light()
                    dismissCameraTutorial()
                }
                .font(PigeonTheme.captionFont)
                .foregroundStyle(PigeonTheme.tertiaryText)
                .padding(.trailing, 8)
                
                Button("Next") {
                    Haptics.light()
                    advanceCameraStep()
                }
                .buttonStyle(PigeonButtonStyle())
            }
            .padding(.top, 2)
        }
        .padding(20)
        .background(PigeonTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 4)
    }
    
    private func advanceCameraStep() {
        if currentStep == .subjects {
            withAnimation(.easeInOut(duration: 0.35)) {
                currentStep = .lockMode
            }
        } else {
            dismissCameraTutorial()
        }
    }
    
    private func dismissCameraTutorial() {
        withAnimation(.easeOut(duration: 0.3)) {
            animateIn = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isShowing = false
            onFinished()
        }
    }
}

