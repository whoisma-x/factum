//
//  FactumTheme.swift
//  Factum
//
//  Factum app theme - warm, imperfect, wabi-sabi
//

import SwiftUI

struct FactumTheme {
    // MARK: - Colors (warm tinted — parchment light, inky dark)
    static let background = Color(light: Color(red: 0.98, green: 0.97, blue: 0.95), dark: Color(red: 0.06, green: 0.06, blue: 0.05))
    static let cardBackground = Color(light: Color(red: 0.94, green: 0.93, blue: 0.90), dark: Color(red: 0.13, green: 0.12, blue: 0.11))
    static let surfaceBackground = Color(light: Color(red: 0.91, green: 0.90, blue: 0.87), dark: Color(red: 0.09, green: 0.08, blue: 0.07))
    static let elevated = Color(light: Color(red: 0.92, green: 0.91, blue: 0.88), dark: Color(red: 0.19, green: 0.18, blue: 0.16))
    static let primaryText = Color(light: Color(red: 0.12, green: 0.11, blue: 0.10), dark: Color(red: 0.93, green: 0.91, blue: 0.88))
    static let secondaryText = Color(light: Color(red: 0.42, green: 0.40, blue: 0.37), dark: Color(red: 0.60, green: 0.58, blue: 0.54))
    static let tertiaryText = Color(light: Color(red: 0.55, green: 0.53, blue: 0.49), dark: Color(red: 0.43, green: 0.41, blue: 0.38))
    static let accent = Color(light: Color(red: 0.82, green: 0.80, blue: 0.75), dark: Color(red: 0.28, green: 0.26, blue: 0.23))
    /// Text on accent-colored backgrounds (buttons, selected segments)
    static let accentText = Color(light: Color(red: 0.12, green: 0.11, blue: 0.10), dark: Color(red: 0.93, green: 0.91, blue: 0.88))
    static let separator = Color(light: Color(red: 0.84, green: 0.82, blue: 0.78), dark: Color(red: 0.22, green: 0.20, blue: 0.18))
    static let destructive = Color(red: 0.78, green: 0.28, blue: 0.24)

    // MARK: - Font (Serif, light weight — thin and quiet)
    static func font(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let titleFont = Font.system(size: 26, weight: .light, design: .serif)
    static let headlineFont = Font.system(size: 20, weight: .light, design: .serif)
    static let subheadlineFont = Font.system(size: 16, weight: .light, design: .serif)
    static let bodyFont = Font.system(size: 15, weight: .light, design: .serif)
    static let captionFont = Font.system(size: 13, weight: .light, design: .serif)
    static let smallFont = Font.system(size: 11, weight: .light, design: .serif)
}

// MARK: - Adaptive Color Extension

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}

// MARK: - Organic Shape (slightly uneven corners — handmade feel)

/// A rounded rectangle with subtly uneven corners, like hand-cut paper.
struct OrganicRect: InsettableShape {
    var base: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let tl = base * 0.85
        let tr = base * 1.1
        let bl = base * 1.0
        let br = base * 0.9
        return UnevenRoundedRectangle(
            topLeadingRadius: tl,
            bottomLeadingRadius: bl,
            bottomTrailingRadius: br,
            topTrailingRadius: tr
        ).path(in: r)
    }

    func inset(by amount: CGFloat) -> OrganicRect {
        OrganicRect(base: base, insetAmount: insetAmount + amount)
    }
}

// MARK: - Reusable Modifiers

struct FactumCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(FactumTheme.cardBackground)
            .clipShape(OrganicRect(base: 14))
    }
}

struct FactumButtonStyle: ButtonStyle {
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FactumTheme.subheadlineFont)
            .foregroundStyle(filled ? FactumTheme.accentText : FactumTheme.primaryText)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(filled ? FactumTheme.accent : Color.clear)
            .clipShape(OrganicRect(base: 10))
            .overlay(
                OrganicRect(base: 10)
                    .strokeBorder(FactumTheme.accent, lineWidth: filled ? 0 : 1.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func factumCard() -> some View {
        modifier(FactumCardModifier())
    }
}
