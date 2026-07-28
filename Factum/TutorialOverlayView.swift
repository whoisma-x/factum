//
//  TutorialOverlayView.swift
//  Factum
//
//  Post-onboarding coach marks tutorial
//

import SwiftUI

// MARK: - Tutorial Steps

enum TutorialStep: Int, CaseIterable {
    case recordButton = 0
    case feedTab = 1
    case profileTab = 2
    case subjects = 3
    case lockMode = 4
    case stats = 5
    
    var title: String {
        switch self {
        case .recordButton: return "Start Recording"
        case .feedTab:      return "Your Feed"
        case .profileTab:   return "Your Profile"
        case .subjects:     return "Study Subjects"
        case .lockMode:     return "Lock Mode"
        case .stats:        return "Detailed Stats"
        }
    }
    
    var description: String {
        switch self {
        case .recordButton: return "Tap here to start a study session. Choose from continuous, pomodoro, or timed recording."
        case .feedTab:      return "Your study sessions appear here. Watch your timelapses and track your progress."
        case .profileTab:   return "View your stats, streaks, and total study time. Edit your profile here."
        case .subjects:     return "Pick a subject before you start studying — swipe to see more or tap + New to create one. You can also switch subjects mid-session by tapping the subject pill."
        case .lockMode:     return "Enable lock mode during a session to automatically end and save your progress when you leave the app. It also hides the pause button so you can't accidentally interrupt your session."
        case .stats:        return "Detailed breakdowns of your study habits — weekly, monthly, and yearly."
        }
    }
    
    var icon: String {
        switch self {
        case .recordButton: return "video.fill"
        case .feedTab:      return "house.fill"
        case .profileTab:   return "person.circle.fill"
        case .subjects:     return "book.fill"
        case .lockMode:     return "lock.fill"
        case .stats:        return "chart.bar.fill"
        }
    }
    
    var buttonLabel: String {
        self == .stats ? "Got it" : "Next"
    }
    
    var isLast: Bool {
        self == .stats
    }
    
    /// Whether this step highlights a specific tab bar item with a spotlight cutout
    var hasSpotlight: Bool {
        rawValue <= 2
    }
    
    /// Tab index to switch to when this step becomes active
    var targetTab: Int? {
        switch self {
        case .recordButton: return nil
        case .feedTab:      return 0
        case .profileTab:   return 4
        case .subjects:     return 4
        case .lockMode:     return 4
        case .stats:        return 4
        }
    }
    
    /// Which tab index the spotlight targets (for arrow positioning)
    var spotlightTabIndex: Int {
        switch self {
        case .recordButton: return 2
        case .feedTab:      return 0
        case .profileTab:   return 4
        default:            return 0
        }
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

struct TutorialOverlayView: View {
    @Binding var isShowing: Bool
    @Binding var selectedTab: Int
    /// The actual tab bar frame in global coordinates, passed from ContentView.
    let tabBarFrame: CGRect
    @State private var currentStep: TutorialStep = .recordButton
    @State private var animateIn = false
    
    var body: some View {
        GeometryReader { geometry in
            let spotlight = spotlightRect(for: currentStep)
            
            ZStack {
                // Background overlay
                if currentStep.hasSpotlight {
                    SpotlightOverlay(targetRect: spotlight)
                        .transition(.opacity)
                } else {
                    Color.black.opacity(0.65)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
                
                // Tooltip card with arrow — all steps get an arrow
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
            // Block taps from reaching content below
            .contentShape(Rectangle())
            .onTapGesture { }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Spotlight Position Calculation (uses real tab bar frame)
    
    private func spotlightRect(for step: TutorialStep) -> CGRect {
        guard step.hasSpotlight else { return .zero }
        
        // tabBarFrame is the GlassEffectContainer's frame (before outer padding).
        // Inside it: HStack with .padding(.horizontal, 12), .padding(.vertical, 8)
        // Each of the 5 tab buttons is 52x52 with .frame(maxWidth: .infinity)
        let innerHPad: CGFloat = 12
        let innerVPad: CGFloat = 8
        let buttonFrame: CGFloat = 52
        
        let contentLeft = tabBarFrame.minX + innerHPad
        let contentWidth = tabBarFrame.width - innerHPad * 2
        let tabWidth = contentWidth / 5.0
        
        let tabIndex = step.spotlightTabIndex
        let cx = contentLeft + tabWidth * CGFloat(tabIndex) + tabWidth / 2
        let cy = tabBarFrame.minY + innerVPad + buttonFrame / 2
        
        // Spotlight sized to fit the icon snugly (icon is ~20pt, spotlight 36pt)
        let spotSize: CGFloat = 36
        
        return CGRect(
            x: cx - spotSize / 2,
            y: cy - spotSize / 2,
            width: spotSize,
            height: spotSize
        )
    }
    
    // MARK: - Tooltip with Arrow
    
    private func tooltipWithArrow(in geometry: GeometryProxy, spotlightRect: CGRect) -> some View {
        let screenWidth = geometry.size.width
        let screenHeight = geometry.size.height
        
        // For spotlight steps, arrow points at the highlighted icon.
        // For non-spotlight steps, arrow points at center of tab bar.
        let arrowCenterX: CGFloat
        let anchorY: CGFloat
        if currentStep.hasSpotlight {
            arrowCenterX = spotlightRect.midX
            anchorY = spotlightRect.minY - 12
        } else {
            arrowCenterX = tabBarFrame.midX
            anchorY = tabBarFrame.minY - 12
        }
        
        let bottomPad = max(0, screenHeight - anchorY)
        
        return VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 0) {
                cardContent
                
                // Arrow pointing down — only for spotlight steps that
                // highlight a specific tab bar item
                if currentStep.hasSpotlight {
                    TooltipArrow()
                        .fill(FactumTheme.cardBackground)
                        .frame(width: 16, height: 10)
                        .offset(x: arrowCenterX - screenWidth / 2)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, bottomPad)
    }
    
    // MARK: - Card Content
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Icon + title row
            HStack(spacing: 10) {
                Image(systemName: currentStep.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(FactumTheme.secondaryText)
                
                Text(currentStep.title)
                    .font(FactumTheme.headlineFont)
                    .foregroundStyle(FactumTheme.primaryText)
            }
            
            Text(currentStep.description)
                .font(FactumTheme.font(16, weight: .light))
                .foregroundStyle(FactumTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                // Step indicator dots
                HStack(spacing: 6) {
                    ForEach(TutorialStep.allCases, id: \.rawValue) { step in
                        Circle()
                            .fill(step == currentStep ? FactumTheme.primaryText : FactumTheme.separator)
                            .frame(width: 6, height: 6)
                    }
                }
                
                Spacer()
                
                // Skip button (except on last step)
                if !currentStep.isLast {
                    Button("Skip") {
                        dismissTutorial()
                    }
                    .font(FactumTheme.captionFont)
                    .foregroundStyle(FactumTheme.tertiaryText)
                    .padding(.trailing, 8)
                }
                
                // Next / Got it button
                Button(currentStep.buttonLabel) {
                    advanceStep()
                }
                .buttonStyle(FactumButtonStyle())
            }
            .padding(.top, 2)
        }
        .padding(20)
        .background(FactumTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 4)
    }
    
    // MARK: - Step Navigation
    
    private func advanceStep() {
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
