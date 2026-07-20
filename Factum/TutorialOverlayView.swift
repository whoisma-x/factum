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
    case stats = 4
    
    var title: String {
        switch self {
        case .recordButton: return "Start Recording"
        case .feedTab:      return "Your Feed"
        case .profileTab:   return "Your Profile"
        case .subjects:     return "Study Subjects"
        case .stats:        return "Detailed Stats"
        }
    }
    
    var description: String {
        switch self {
        case .recordButton: return "Tap here to start a study session. Choose from continuous, pomodoro, or timed recording."
        case .feedTab:      return "Your study sessions appear here. Watch your timelapses and track your progress."
        case .profileTab:   return "View your stats, streaks, and total study time. Edit your profile here."
        case .subjects:     return "Organize your sessions by subject. Manage them in Settings."
        case .stats:        return "Detailed breakdowns of your study habits — weekly, monthly, and yearly."
        }
    }
    
    var icon: String {
        switch self {
        case .recordButton: return "video.fill"
        case .feedTab:      return "house.fill"
        case .profileTab:   return "person.circle.fill"
        case .subjects:     return "book.fill"
        case .stats:        return "chart.bar.fill"
        }
    }
    
    var buttonLabel: String {
        self == .stats ? "Got it" : "Next"
    }
    
    var isLast: Bool {
        self == .stats
    }
    
    /// Whether this step highlights a tab bar item (vs. centered tooltip)
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
        case .stats:        return 4
        }
    }
}

// MARK: - Spotlight Overlay (dimmed background with cutout)

struct SpotlightOverlay: View {
    let targetRect: CGRect
    let cornerRadius: CGFloat = 16
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geo.size))
                path.addRoundedRect(
                    in: targetRect.insetBy(dx: -10, dy: -10),
                    cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
                )
            }
            .fill(style: FillStyle(eoFill: true))
            .foregroundStyle(Color.black.opacity(0.6))
        }
        .ignoresSafeArea()
    }
}

// MARK: - Tutorial Overlay View

struct TutorialOverlayView: View {
    @Binding var isShowing: Bool
    @Binding var selectedTab: Int
    @State private var currentStep: TutorialStep = .recordButton
    @State private var animateIn = false
    
    var body: some View {
        GeometryReader { geometry in
            let spotlight = spotlightRect(for: currentStep, in: geometry)
            
            ZStack {
                // Background overlay
                if currentStep.hasSpotlight {
                    SpotlightOverlay(targetRect: spotlight)
                        .transition(.opacity)
                } else {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
                
                // Tooltip card
                tooltipCard(in: geometry, spotlightRect: spotlight)
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
    }
    
    // MARK: - Spotlight Position Calculation
    
    private func spotlightRect(for step: TutorialStep, in geometry: GeometryProxy) -> CGRect {
        let screenWidth = geometry.size.width
        let screenHeight = geometry.size.height
        let safeBottom = geometry.safeAreaInsets.bottom
        
        // Tab bar layout constants (matching ContentView's customTabBar):
        // GlassEffectContainer has outer padding: .horizontal(2), .bottom(2)
        // Inner HStack has .padding(.horizontal, 12), .padding(.vertical, 8)
        // Each tab button is 52x52 with .frame(maxWidth: .infinity)
        let outerHPad: CGFloat = 2
        let innerHPad: CGFloat = 12
        let outerBottomPad: CGFloat = 2
        let innerVPad: CGFloat = 8
        let buttonSize: CGFloat = 52
        let tabBarHeight = buttonSize + innerVPad * 2
        
        let tabBarContentWidth = screenWidth - (outerHPad * 2) - (innerHPad * 2)
        let tabWidth = tabBarContentWidth / 5.0
        let tabBarLeft = outerHPad + innerHPad
        let tabBarTop = screenHeight - safeBottom - outerBottomPad - tabBarHeight
        
        func tabCenterX(index: Int) -> CGFloat {
            tabBarLeft + tabWidth * CGFloat(index) + tabWidth / 2
        }
        
        let spotSize: CGFloat = 56
        
        switch step {
        case .recordButton:
            let cx = tabCenterX(index: 2)
            return CGRect(
                x: cx - spotSize / 2,
                y: tabBarTop + (tabBarHeight - spotSize) / 2,
                width: spotSize,
                height: spotSize
            )
        case .feedTab:
            let cx = tabCenterX(index: 0)
            return CGRect(
                x: cx - spotSize / 2,
                y: tabBarTop + (tabBarHeight - spotSize) / 2,
                width: spotSize,
                height: spotSize
            )
        case .profileTab:
            let cx = tabCenterX(index: 4)
            return CGRect(
                x: cx - spotSize / 2,
                y: tabBarTop + (tabBarHeight - spotSize) / 2,
                width: spotSize,
                height: spotSize
            )
        case .subjects, .stats:
            // No spotlight — return zero rect
            return .zero
        }
    }
    
    // MARK: - Tooltip Card
    
    private func tooltipCard(in geometry: GeometryProxy, spotlightRect: CGRect) -> some View {
        VStack(spacing: 0) {
            if currentStep.hasSpotlight {
                Spacer()
                cardContent
                    .padding(.horizontal, 24)
                    .padding(.bottom, geometry.size.height - spotlightRect.minY + 24)
            } else {
                Spacer()
                cardContent
                    .padding(.horizontal, 24)
                Spacer()
            }
        }
    }
    
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
                .font(FactumTheme.bodyFont)
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
        .clipShape(OrganicRect(base: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
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
