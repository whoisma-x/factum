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

    // MARK: - Spacing Scale
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32
    
    // MARK: - Corner Radii
    static let cornerBadge: CGFloat = 8       // Tags, badges, small chips
    static let cornerField: CGFloat = 12      // Text fields, list rows
    static let cornerCard: CGFloat = 14       // Cards, containers
    static let cornerSheet: CGFloat = 22      // Sheets, modals, tab bar

    // MARK: - Shadows (subtle depth — cards feel layered, not flat)
    static let cardShadow: Color = Color(light: Color.black.opacity(0.06), dark: Color.black.opacity(0.3))
    static let cardShadowRadius: CGFloat = 8
    static let cardShadowY: CGFloat = 2

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
    static let sectionTitleFont = Font.system(size: 14, weight: .semibold, design: .serif)
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
            .shadow(color: FactumTheme.cardShadow, radius: FactumTheme.cardShadowRadius, x: 0, y: FactumTheme.cardShadowY)
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
    
    func factumSectionTitle() -> some View {
        modifier(FactumSectionTitleModifier())
    }
}

struct FactumSectionTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(FactumTheme.sectionTitleFont)
            .foregroundStyle(FactumTheme.tertiaryText)
            .textCase(.uppercase)
            .tracking(1)
    }
}

// MARK: - Haptics

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Instagram Stories Sticker

/// A transparent sticker view for Instagram Stories showing study session stats.
/// Supports multiple layout formats via the `layout` parameter.
struct InstagramStickerView: View {
    let durationSeconds: Int
    let subjectName: String
    let subjectColor: Color
    let appLeaveCount: Int
    var caption: String = ""
    var studyDescription: String = ""
    var subjectSegments: [SubjectSegment] = []
    var subjectColorResolver: ((String) -> Color)? = nil
    var layout: StickerLayout = .stack
    var customConfig: CustomStickerConfig? = nil

    private var formattedDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        let s = durationSeconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    private var hasMultipleSubjects: Bool { subjectSegments.count > 1 }
    private var hasCaption: Bool { !caption.isEmpty || !studyDescription.isEmpty }

    private let pillBg = Color.black.opacity(0.55)
    private let pillRadius: CGFloat = 14
    private let glassesSize: CGFloat = 10
    private let glassesOpacity: Double = 0.2

    var body: some View {
        switch layout {
        case .stack: stackLayout
        case .card: cardLayout
        case .bar: barLayout
        case .badge: badgeLayout
        case .minimal: minimalLayout
        case .timeOnly: durationPill
        case .subjectOnly: subjectPill
        case .captionOnly: captionPill
        case .focusOnly: focusPill
        case .appLeaves: appLeavesPill
        case .breakdown: breakdownPill
        case .branding: brandingPill
        case .notesClean: notesCleanLayout
        case .polaroid: polaroidLayout
        case .filmStrip: filmStripLayout
        case .notebook: notebookLayout
        case .receipt: receiptLayout
        case .stamp: stampLayout
        case .custom: customLayout
        }
    }

    // MARK: - Stack (vertical pills, original look)

    private var stackLayout: some View {
        VStack(spacing: 8) {
            if hasCaption { captionPill }
            durationPill
            subjectPill
            focusPill
        }
        .frame(width: 260)
    }

    // MARK: - Card (single rounded card, everything inside)

    private var cardLayout: some View {
        VStack(spacing: 10) {
            if hasCaption {
                VStack(spacing: 4) {
                    if !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    if !studyDescription.isEmpty {
                        Text(studyDescription)
                            .font(.system(size: 11, weight: .regular, design: .serif))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
            }

            Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.horizontal, 8)

            // Big time
            Text(formattedDuration)
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            Text("studied")
                .font(.system(size: 12, weight: .light, design: .serif))
                .foregroundStyle(.white.opacity(0.45))

            Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.horizontal, 8)

            // Subject(s)
            if hasMultipleSubjects {
                VStack(spacing: 5) {
                    ForEach(subjectSegments) { seg in
                        HStack(spacing: 6) {
                            Circle().fill(subjectColorResolver?(seg.subject) ?? subjectColor).frame(width: 7, height: 7)
                            Text(seg.subject)
                                .font(.system(size: 11, weight: .regular, design: .serif))
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Text(formatSegmentTime(seg.seconds))
                                .font(.system(size: 11, weight: .regular, design: .serif))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Circle().fill(subjectColor).frame(width: 8, height: 8)
                    Text(subjectName)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            // Focus
            HStack(spacing: 5) {
                Image(systemName: appLeaveCount == 0 ? "checkmark.circle.fill" : "iphone.and.arrow.forward")
                    .font(.system(size: 11))
                    .foregroundStyle(appLeaveCount == 0 ? .green : .white.opacity(0.45))
                Text(focusText)
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 240)
        .overlay(alignment: .bottomTrailing) {
            FactumIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(pillBg))
    }

    // MARK: - Bar (horizontal strip for bottom of story)

    private var barLayout: some View {
        HStack(spacing: 14) {
            // Duration
            VStack(spacing: 2) {
                Text(formattedDuration)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text("studied")
                    .font(.system(size: 9, weight: .light, design: .serif))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 28)

            // Subject
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(subjectColor).frame(width: 6, height: 6)
                    Text(subjectName)
                        .font(.system(size: 12, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                Text(focusText)
                    .font(.system(size: 9, weight: .regular, design: .serif))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            if hasCaption {
                Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 28)
                Text(caption)
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            FactumIcon(size: glassesSize, color: .white.opacity(glassesOpacity))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(pillBg))
    }

    // MARK: - Badge (compact corner badge)

    private var badgeLayout: some View {
        VStack(spacing: 4) {
            Text(formattedDuration)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            HStack(spacing: 4) {
                Circle().fill(subjectColor).frame(width: 6, height: 6)
                Text(subjectName)
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            HStack(spacing: 3) {
                Image(systemName: appLeaveCount == 0 ? "checkmark.circle.fill" : "iphone.and.arrow.forward")
                    .font(.system(size: 8))
                    .foregroundStyle(appLeaveCount == 0 ? .green : .white.opacity(0.4))
                Text(focusText)
                    .font(.system(size: 9, weight: .regular, design: .serif))
                    .foregroundStyle(.white.opacity(0.5))
            }

            FactumIcon(size: 8, color: .white.opacity(glassesOpacity))
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(pillBg))
    }

    // MARK: - Minimal (big time + subject, nothing else)

    private var minimalLayout: some View {
        VStack(spacing: 6) {
            Text(formattedDuration)
                .font(.system(size: 36, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            HStack(spacing: 5) {
                Circle().fill(subjectColor).frame(width: 7, height: 7)
                Text(subjectName)
                    .font(.system(size: 14, weight: .light, design: .serif))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .overlay(alignment: .bottomTrailing) {
            FactumIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(pillBg))
    }

    // MARK: - Polaroid (classic photo frame with stats below)

    private var polaroidLayout: some View {
        VStack(spacing: 0) {
            // Photo area (transparent — user's story shows through)
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.03))
                .frame(width: 200, height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
                .padding(.top, 12)
                .padding(.horizontal, 14)

            // Caption area below photo
            VStack(spacing: 4) {
                if !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(formattedDuration)
                            .font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    HStack(spacing: 4) {
                        Circle().fill(subjectColor).frame(width: 5, height: 5)
                        Text(subjectName)
                            .font(.system(size: 11, weight: .regular, design: .serif))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
        }
        .frame(width: 228)
        .overlay(alignment: .bottomTrailing) {
            FactumIcon(size: 8, color: .white.opacity(0.15)).padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.6)))
    }

    // MARK: - Film Strip (sprocket holes + frames)

    private var filmStripLayout: some View {
        HStack(spacing: 0) {
            // Left sprocket holes
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white.opacity(0.15))
                        .frame(width: 6, height: 10)
                }
            }
            .padding(.horizontal, 5)

            // Content
            VStack(spacing: 6) {
                Text(formattedDuration)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(1)

                Rectangle().fill(.white.opacity(0.1)).frame(height: 1)

                HStack(spacing: 4) {
                    Circle().fill(subjectColor).frame(width: 6, height: 6)
                    Text(subjectName)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }

                if hasCaption {
                    Text(caption)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                HStack(spacing: 3) {
                    Image(systemName: appLeaveCount == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.system(size: 8))
                        .foregroundStyle(appLeaveCount == 0 ? .green.opacity(0.7) : .white.opacity(0.4))
                    Text(focusText)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)

            // Right sprocket holes
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white.opacity(0.15))
                        .frame(width: 6, height: 10)
                }
            }
            .padding(.horizontal, 5)
        }
        .overlay(alignment: .bottomTrailing) {
            FactumIcon(size: 8, color: .white.opacity(0.15)).padding(6)
        }
        .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.08, green: 0.07, blue: 0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Notebook (lined paper look)

    private var notebookLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header line
            HStack(spacing: 6) {
                Text("STUDY LOG")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(2)
                Spacer()
                FactumIcon(size: 8, color: .white.opacity(0.15))
            }
            .padding(.bottom, 8)

            // Ruled lines with content
            VStack(alignment: .leading, spacing: 0) {
                notebookLine {
                    HStack(spacing: 6) {
                        Text(formattedDuration)
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                        Text("studied")
                            .font(.system(size: 12, weight: .light, design: .serif))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                notebookLine {
                    HStack(spacing: 5) {
                        Circle().fill(subjectColor).frame(width: 7, height: 7)
                        Text(subjectName)
                            .font(.system(size: 12, weight: .regular, design: .serif))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }

                if hasMultipleSubjects {
                    ForEach(subjectSegments) { seg in
                        notebookLine {
                            HStack(spacing: 5) {
                                Text("·")
                                    .foregroundStyle(subjectColorResolver?(seg.subject) ?? subjectColor)
                                Text(seg.subject)
                                    .font(.system(size: 10, weight: .regular, design: .serif))
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Text(formatSegmentTime(seg.seconds))
                                    .font(.system(size: 10, weight: .regular, design: .serif))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                    }
                }

                notebookLine {
                    HStack(spacing: 4) {
                        Image(systemName: appLeaveCount == 0 ? "checkmark" : "arrow.right.square")
                            .font(.system(size: 9))
                            .foregroundStyle(appLeaveCount == 0 ? .green.opacity(0.7) : .white.opacity(0.4))
                        Text(focusText)
                            .font(.system(size: 10, weight: .regular, design: .serif))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                if hasCaption {
                    notebookLine {
                        Text("\"" + caption + "\"")
                            .font(.system(size: 10, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 220)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.6))
                // Red margin line
                Rectangle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 1)
                    .padding(.leading, 26)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func notebookLine<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
            }
    }

    // MARK: - Receipt (thermal printer style)

    private var receiptLayout: some View {
        VStack(spacing: 0) {
            // Torn edge top
            ZigzagEdge()
                .fill(.white.opacity(0.08))
                .frame(height: 6)

            VStack(spacing: 6) {
                FactumIcon(size: 14, color: .white.opacity(0.25))
                    .padding(.top, 4)

                Text("STUDY RECEIPT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(3)

                dottedLine

                receiptRow("TIME", formattedDuration)
                receiptRow("SUBJECT", subjectName)

                if hasMultipleSubjects {
                    ForEach(subjectSegments) { seg in
                        receiptRow("  " + seg.subject, formatSegmentTime(seg.seconds))
                    }
                }

                receiptRow("FOCUS", focusText)

                if hasCaption {
                    receiptRow("NOTE", caption)
                }

                dottedLine

                receiptRow("TOTAL", formattedDuration, bold: true)

                dottedLine

                Text("— thank you for studying —")
                    .font(.system(size: 7, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            // Torn edge bottom
            ZigzagEdge()
                .fill(.white.opacity(0.08))
                .frame(height: 6)
                .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
        }
        .frame(width: 180)
        .background(Color.black.opacity(0.65))
    }

    private func receiptRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: bold ? .bold : .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(bold ? 0.9 : 0.65))
                .lineLimit(1)
        }
    }

    private var dottedLine: some View {
        GeometryReader { geo in
            let dotCount = max(1, Int(geo.size.width / 4.5))
            HStack(spacing: 3) {
                ForEach(0..<dotCount, id: \.self) { _ in
                    Circle().fill(.white.opacity(0.12)).frame(width: 1.5, height: 1.5)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 2)
    }

    // MARK: - Stamp (postage stamp look)

    private var stampLayout: some View {
        VStack(spacing: 6) {
            // Value (time)
            Text(formattedDuration)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            // Subject
            HStack(spacing: 5) {
                Circle().fill(subjectColor).frame(width: 7, height: 7)
                Text(subjectName.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(1.5)
            }

            // Branding
            FactumIcon(size: 10, color: .white.opacity(0.2))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            // Perforated stamp border
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                .foregroundStyle(.white.opacity(0.15))
        )
        .padding(4)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Custom (user-configurable)

    private var customLayout: some View {
        let config = customConfig ?? CustomStickerConfig.load()
        let fontDesign: Font.Design = {
            switch config.fontStyle {
            case .serif: return .serif
            case .mono: return .monospaced
            case .sans: return .default
            }
        }()
        let align = config.swiftUIAlignment

        return Group {
            switch config.arrangement {
            case .vertical:
                customVertical(config: config, fontDesign: fontDesign, align: align)
            case .horizontal:
                customHorizontal(config: config, fontDesign: fontDesign)
            case .compact:
                customCompact(config: config, fontDesign: fontDesign, align: align)
            }
        }
        .padding(.horizontal, config.backgroundStyle == .transparent ? 0 : 18)
        .padding(.vertical, config.backgroundStyle == .transparent ? 0 : 14)
        .background(customBackground(config.backgroundStyle))
    }

    @ViewBuilder
    private func customBackground(_ style: CustomStickerConfig.BackgroundStyle) -> some View {
        switch style {
        case .rounded:
            RoundedRectangle(cornerRadius: 14).fill(pillBg)
        case .pill:
            Capsule().fill(pillBg)
        case .sharp:
            Rectangle().fill(pillBg)
        case .transparent:
            Color.clear
        }
    }

    /// Renders a single custom element by index.
    @ViewBuilder
    private func customElement(_ index: Int, config: CustomStickerConfig, fontDesign: Font.Design) -> some View {
        switch index {
        case 0: // Duration
            if config.showDuration {
                Text(formattedDuration)
                    .font(.system(size: config.durationSize(base: 28), weight: .bold, design: fontDesign))
                    .foregroundStyle(.white)
            }
        case 1: // Subject
            if config.showSubject {
                if hasMultipleSubjects && config.showBreakdown {
                    VStack(spacing: 5) {
                        ForEach(subjectSegments) { seg in
                            HStack(spacing: 5) {
                                Circle().fill(subjectColorResolver?(seg.subject) ?? subjectColor).frame(width: 7, height: 7)
                                Text(seg.subject)
                                    .font(.system(size: config.labelSize(base: 11), weight: .regular, design: fontDesign))
                                    .foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Text(formatSegmentTime(seg.seconds))
                                    .font(.system(size: config.labelSize(base: 11), weight: .regular, design: fontDesign))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Circle().fill(subjectColor).frame(width: 8, height: 8)
                        Text(subjectName)
                            .font(.system(size: config.labelSize(base: 13), weight: .regular, design: fontDesign))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        case 2: // Breakdown (handled by subject)
            EmptyView()
        case 3: // Focus
            if config.showFocus {
                HStack(spacing: 5) {
                    Image(systemName: appLeaveCount == 0 ? "checkmark.circle.fill" : "iphone.and.arrow.forward")
                        .font(.system(size: config.labelSize(base: 11)))
                        .foregroundStyle(appLeaveCount == 0 ? .green : .white.opacity(0.45))
                    Text(focusText)
                        .font(.system(size: config.labelSize(base: 11), weight: .regular, design: fontDesign))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        case 4: // Caption
            if config.showCaption && hasCaption {
                Text(caption)
                    .font(.system(size: config.labelSize(base: 11), weight: .regular, design: fontDesign))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .multilineTextAlignment(config.swiftUIMultilineAlignment)
            }
        case 5: // Branding
            if config.showBranding {
                FactumIcon(size: glassesSize, color: .white.opacity(glassesOpacity))
            }
        default:
            EmptyView()
        }
    }

    private func customVertical(config: CustomStickerConfig, fontDesign: Font.Design, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 8) {
            ForEach(config.elementOrder.filter { $0 != 2 }, id: \.self) { idx in
                customElement(idx, config: config, fontDesign: fontDesign)
            }
        }
    }

    private func customHorizontal(config: CustomStickerConfig, fontDesign: Font.Design) -> some View {
        HStack(spacing: 12) {
            ForEach(config.elementOrder.filter { $0 != 2 }, id: \.self) { idx in
                customElement(idx, config: config, fontDesign: fontDesign)
            }
        }
    }

    private func customCompact(config: CustomStickerConfig, fontDesign: Font.Design, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 4) {
            HStack(spacing: 10) {
                ForEach(config.elementOrder.filter { [0, 1, 5].contains($0) }, id: \.self) { idx in
                    customElement(idx, config: config, fontDesign: fontDesign)
                }
            }
            ForEach(config.elementOrder.filter { [3, 4].contains($0) }, id: \.self) { idx in
                customElement(idx, config: config, fontDesign: fontDesign)
            }
        }
    }

    // MARK: - Shared pill components

    private var captionPill: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                if !caption.isEmpty && !studyDescription.isEmpty {
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(height: 1)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                }
                if !studyDescription.isEmpty {
                    Text(studyDescription)
                        .font(.system(size: 11, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .overlay(alignment: .bottomTrailing) {
            FactumIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
        }
        .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    private var durationPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
            Text(formattedDuration)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            Text("studied")
                .font(.system(size: 13, weight: .light, design: .serif))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottomTrailing) {
            FactumIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
        }
        .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    private var subjectPill: some View {
        Group {
            if hasMultipleSubjects {
                VStack(spacing: 6) {
                    ForEach(subjectSegments) { seg in
                        HStack(spacing: 6) {
                            Circle().fill(subjectColorResolver?(seg.subject) ?? subjectColor).frame(width: 8, height: 8)
                            Text(seg.subject)
                                .font(.system(size: 12, weight: .regular, design: .serif))
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Text(formatSegmentTime(seg.seconds))
                                .font(.system(size: 12, weight: .regular, design: .serif))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .overlay(alignment: .bottomTrailing) {
                    FactumIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
                }
                .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
            } else {
                HStack(spacing: 7) {
                    Circle().fill(subjectColor).frame(width: 9, height: 9)
                    Text(subjectName)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .overlay(alignment: .bottomTrailing) {
                    FactumIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
                }
                .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
            }
        }
    }

    private var focusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: appLeaveCount == 0 ? "checkmark.circle.fill" : "iphone.and.arrow.forward")
                .font(.system(size: 13))
                .foregroundStyle(appLeaveCount == 0 ? .green : .white.opacity(0.55))
            Text(focusText)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .overlay(alignment: .bottomTrailing) {
            FactumIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
        }
        .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    // MARK: - App Leaves pill (just the leave count)

    private var appLeavesPill: some View {
        HStack(spacing: 6) {
            Image(systemName: appLeaveCount == 0 ? "checkmark.circle.fill" : "iphone.and.arrow.forward")
                .font(.system(size: 13))
                .foregroundStyle(appLeaveCount == 0 ? .green : .white.opacity(0.55))
            if appLeaveCount == 0 {
                Text("No leaves")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Text("\(appLeaveCount)")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text(appLeaveCount == 1 ? "leave" : "leaves")
                    .font(.system(size: 13, weight: .light, design: .serif))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottomTrailing) {
            FactumIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
        }
        .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    // MARK: - Breakdown pill (subject time breakdown)

    private var breakdownPill: some View {
        VStack(spacing: 6) {
            if hasMultipleSubjects {
                ForEach(subjectSegments) { seg in
                    HStack(spacing: 6) {
                        Circle().fill(subjectColorResolver?(seg.subject) ?? subjectColor).frame(width: 8, height: 8)
                        Text(seg.subject)
                            .font(.system(size: 12, weight: .regular, design: .serif))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Text(formatSegmentTime(seg.seconds))
                            .font(.system(size: 12, weight: .regular, design: .serif))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Circle().fill(subjectColor).frame(width: 8, height: 8)
                    Text(subjectName)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text(formattedDuration)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .bottomTrailing) {
            FactumIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
        }
        .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    // MARK: - Branding pill (just the logo)

    private var brandingPill: some View {
        FactumIcon(size: 28, color: .white.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    // MARK: - Notes Clean (notebook without title header)

    private var notesCleanLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            notebookLine {
                HStack(spacing: 6) {
                    Text(formattedDuration)
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text("studied")
                        .font(.system(size: 12, weight: .light, design: .serif))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            notebookLine {
                HStack(spacing: 5) {
                    Circle().fill(subjectColor).frame(width: 7, height: 7)
                    Text(subjectName)
                        .font(.system(size: 12, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            if hasMultipleSubjects {
                ForEach(subjectSegments) { seg in
                    notebookLine {
                        HStack(spacing: 5) {
                            Text("·")
                                .foregroundStyle(subjectColorResolver?(seg.subject) ?? subjectColor)
                            Text(seg.subject)
                                .font(.system(size: 10, weight: .regular, design: .serif))
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Text(formatSegmentTime(seg.seconds))
                                .font(.system(size: 10, weight: .regular, design: .serif))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
            }

            notebookLine {
                HStack(spacing: 4) {
                    Image(systemName: appLeaveCount == 0 ? "checkmark" : "arrow.right.square")
                        .font(.system(size: 9))
                        .foregroundStyle(appLeaveCount == 0 ? .green.opacity(0.7) : .white.opacity(0.4))
                    Text(focusText)
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if hasCaption {
                notebookLine {
                    Text("\"" + caption + "\"")
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(width: 220)
        .overlay(alignment: .bottomTrailing) {
            FactumIcon(size: 8, color: .white.opacity(0.15)).padding(8)
        }
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.6))
                Rectangle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 1)
                    .padding(.leading, 26)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var focusText: String {
        appLeaveCount == 0 ? "Perfect focus" : "\(appLeaveCount) app \(appLeaveCount == 1 ? "leave" : "leaves")"
    }

    private func formatSegmentTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h \(s)s" }
        if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
        return "\(seconds)s"
    }
}

/// Zigzag torn-paper edge for receipt layout.
struct ZigzagEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let zigWidth: CGFloat = 6
        let count = max(1, Int(ceil(rect.width / zigWidth)))
        let actualWidth = rect.width / CGFloat(count)
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        for i in 0..<count {
            let x = CGFloat(i) * actualWidth
            path.addLine(to: CGPoint(x: x + actualWidth / 2, y: rect.minY))
            path.addLine(to: CGPoint(x: x + actualWidth, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

/// Sticker layout formats — different visual arrangements of the same data.
enum StickerLayout: String, CaseIterable, Identifiable {
    // Overlay stickers
    case stack = "Stack"
    case card = "Card"
    case bar = "Bar"
    case badge = "Badge"
    case minimal = "Minimal"
    // Single-element stickers
    case timeOnly = "Time"
    case subjectOnly = "Subject"
    case captionOnly = "Caption"
    case focusOnly = "Focus"
    case appLeaves = "Leaves"
    case breakdown = "Breakdown"
    case branding = "Brand"
    case notesClean = "Notes +"
    // Frame stickers (wrap around photo area)
    case polaroid = "Polaroid"
    case filmStrip = "Film"
    case notebook = "Notes"
    case receipt = "Receipt"
    case stamp = "Stamp"
    // Custom (user-configured)
    case custom = "Custom"

    var id: String { rawValue }
    var label: String { rawValue }
}

/// User-configurable sticker layout persisted in UserDefaults.
struct CustomStickerConfig: Codable, Equatable {
    var showDuration: Bool = true
    var showSubject: Bool = true
    var showBreakdown: Bool = false
    var showFocus: Bool = true
    var showCaption: Bool = false
    var showBranding: Bool = true

    /// Order of elements (indices into the element list)
    var elementOrder: [Int] = [0, 1, 2, 3, 4, 5]  // duration, subject, breakdown, focus, caption, branding

    enum Arrangement: String, Codable, CaseIterable {
        case vertical = "Vertical"
        case horizontal = "Horizontal"
        case compact = "Compact"
    }
    var arrangement: Arrangement = .vertical

    enum BackgroundStyle: String, Codable, CaseIterable {
        case rounded = "Rounded"
        case pill = "Pill"
        case sharp = "Sharp"
        case transparent = "Clear"
    }
    var backgroundStyle: BackgroundStyle = .rounded

    enum FontStyle: String, Codable, CaseIterable {
        case serif = "Serif"
        case mono = "Mono"
        case sans = "Sans"
    }
    var fontStyle: FontStyle = .serif

    enum TextAlignment: String, Codable, CaseIterable {
        case leading = "Left"
        case center = "Center"
        case trailing = "Right"
    }
    var textAlignment: TextAlignment = .center

    enum TextSize: String, Codable, CaseIterable {
        case small = "S"
        case medium = "M"
        case large = "L"
    }
    var textSize: TextSize = .medium

    private static let key = "customStickerConfig"
    private static let presetsKey = "customStickerPresets"

    static func load() -> CustomStickerConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let config = try? JSONDecoder().decode(CustomStickerConfig.self, from: data)
        else { return CustomStickerConfig() }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: - Presets

    struct SavedPreset: Codable, Identifiable {
        let id: UUID
        var name: String
        var config: CustomStickerConfig
    }

    static func loadPresets() -> [SavedPreset] {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let presets = try? JSONDecoder().decode([SavedPreset].self, from: data)
        else { return [] }
        return presets
    }

    static func savePresets(_ presets: [SavedPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }

    func saveAsPreset(name: String) {
        var presets = Self.loadPresets()
        presets.append(SavedPreset(id: UUID(), name: name, config: self))
        Self.savePresets(presets)
    }

    static func deletePreset(id: UUID) {
        var presets = loadPresets()
        presets.removeAll { $0.id == id }
        savePresets(presets)
    }

    // MARK: - Helpers

    var swiftUIAlignment: SwiftUI.HorizontalAlignment {
        switch textAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var swiftUIMultilineAlignment: SwiftUI.TextAlignment {
        switch textAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    func durationSize(base: CGFloat) -> CGFloat {
        switch textSize {
        case .small: return base * 0.8
        case .medium: return base
        case .large: return base * 1.25
        }
    }

    func labelSize(base: CGFloat) -> CGFloat {
        switch textSize {
        case .small: return base * 0.85
        case .medium: return base
        case .large: return base * 1.15
        }
    }
}

/// Shares a study session sticker to Instagram Stories via the URL scheme + pasteboard API.
struct InstagramStoriesSharer {

    /// Share a sticker with the specified layout to Instagram Stories.
    @MainActor
    static func share(
        layout: StickerLayout = .stack,
        durationSeconds: Int,
        subjectName: String,
        subjectColor: Color,
        appLeaveCount: Int,
        caption: String = "",
        studyDescription: String = "",
        subjectSegments: [SubjectSegment] = [],
        subjectColorResolver: ((String) -> Color)? = nil
    ) -> Bool {
        let stickerView = InstagramStickerView(
            durationSeconds: durationSeconds,
            subjectName: subjectName,
            subjectColor: subjectColor,
            appLeaveCount: appLeaveCount,
            caption: caption,
            studyDescription: studyDescription,
            subjectSegments: subjectSegments,
            subjectColorResolver: subjectColorResolver,
            layout: layout
        )

        let renderer = ImageRenderer(content: stickerView)
        renderer.scale = 3

        guard let uiImage = renderer.uiImage,
              let pngData = uiImage.pngData() else { return false }

        return sendSticker(pngData: pngData)
    }

    /// Whether Instagram is available on this device.
    static var isInstagramInstalled: Bool {
        guard let url = URL(string: "instagram-stories://share") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Send PNG data as a sticker to Instagram.
    @MainActor
    private static func sendSticker(pngData: Data) -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "instagram-stories://share?source_application=\(bundleID)") else { return false }
        guard UIApplication.shared.canOpenURL(url) else { return false }

        let pasteboardItems: [[String: Any]] = [
            ["com.instagram.sharedSticker.stickerImage": pngData]
        ]
        let options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(60 * 5)
        ]
        UIPasteboard.general.setItems(pasteboardItems, options: options)

        UIApplication.shared.open(url)
        return true
    }

    /// Share a full 9:16 story as the background image with photo frame and stats.
    @MainActor
    static func shareFullStory(
        durationSeconds: Int,
        subjectName: String,
        subjectColor: Color,
        appLeaveCount: Int,
        isLandscape: Bool,
        photo: UIImage?,
        afterPhoto: UIImage?,
        isTimelapse: Bool,
        videoURL: URL? = nil,
        caption: String = "",
        studyDescription: String = "",
        subjectSegments: [SubjectSegment] = [],
        subjectColorResolver: ((String) -> Color)? = nil
    ) -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "instagram-stories://share?source_application=\(bundleID)") else { return false }
        guard UIApplication.shared.canOpenURL(url) else { return false }

        var pasteboardItem: [String: Any] = [:]

        if let videoURL, let videoData = try? Data(contentsOf: videoURL) {
            // Share video as background with stats sticker overlay
            pasteboardItem["com.instagram.sharedSticker.backgroundVideo"] = videoData

            // Render just the stats as a transparent sticker overlay on the video
            let stickerView = InstagramStickerView(
                durationSeconds: durationSeconds,
                subjectName: subjectName,
                subjectColor: subjectColor,
                appLeaveCount: appLeaveCount,
                caption: caption,
                studyDescription: studyDescription,
                subjectSegments: subjectSegments,
                subjectColorResolver: subjectColorResolver
            )
            let stickerRenderer = ImageRenderer(content: stickerView)
            stickerRenderer.scale = 3
            if let stickerImage = stickerRenderer.uiImage,
               let stickerData = stickerImage.pngData() {
                pasteboardItem["com.instagram.sharedSticker.stickerImage"] = stickerData
            }
        } else {
            // No video — render the full story view as a static background image
            let storyView = InstagramFullStoryView(
                durationSeconds: durationSeconds,
                subjectName: subjectName,
                subjectColor: subjectColor,
                appLeaveCount: appLeaveCount,
                isLandscape: isLandscape,
                photo: photo,
                afterPhoto: afterPhoto,
                isTimelapse: isTimelapse
            )

            let renderer = ImageRenderer(content: storyView.frame(width: 360, height: 640))
            renderer.scale = 3

            guard let uiImage = renderer.uiImage,
                  let pngData = uiImage.pngData() else { return false }

            pasteboardItem["com.instagram.sharedSticker.backgroundImage"] = pngData
        }

        let options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(60 * 5)
        ]
        UIPasteboard.general.setItems([pasteboardItem], options: options)

        UIApplication.shared.open(url)
        return true
    }
}

// MARK: - Full Story View (9:16)

/// A full 9:16 story view with photo frame and study stats, rendered to 1080x1920px.
struct InstagramFullStoryView: View {
    let durationSeconds: Int
    let subjectName: String
    let subjectColor: Color
    let appLeaveCount: Int
    let isLandscape: Bool
    let photo: UIImage?
    let afterPhoto: UIImage?
    let isTimelapse: Bool

    private var formattedDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "0m"
    }

    private let darkBase = Color(red: 0.06, green: 0.06, blue: 0.05)
    private let darkMid = Color(red: 0.13, green: 0.12, blue: 0.11)

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(colors: [darkBase, darkMid, darkBase],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                Spacer().frame(height: isLandscape ? 100 : 40)

                // Photo frame
                photoFrame
                    .padding(.horizontal, 20)

                Spacer().frame(height: 32)

                // Stats panel
                statsPanel

                Spacer()

                // Branding
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 28, height: 1)
                    Text("factum")
                        .font(.system(size: 12, weight: .light, design: .serif))
                        .foregroundStyle(.white.opacity(0.35))
                        .tracking(2)
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 28, height: 1)
                }
                .padding(.bottom, 40)
            }
        }
        .frame(width: 360, height: 640)
    }

    @ViewBuilder
    private var photoFrame: some View {
        if let photo, let afterPhoto {
            // Before/After side by side
            HStack(spacing: 8) {
                imageView(photo, label: "before")
                imageView(afterPhoto, label: "after")
            }
            .frame(height: isLandscape ? 160 : 280)
        } else if let photo {
            // Single photo
            imageView(photo, label: nil)
                .frame(height: isLandscape ? 180 : 340)
        } else {
            // No photo placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.05))
                .frame(height: isLandscape ? 180 : 280)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "timer")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.2))
                        Text("Study Session")
                            .font(.system(size: 12, weight: .light, design: .serif))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private func imageView(_ image: UIImage, label: String?) -> some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )

            // Timelapse badge
            if isTimelapse && label == nil {
                HStack(spacing: 4) {
                    Image(systemName: "timelapse")
                        .font(.system(size: 10, weight: .medium))
                    Text("Timelapse")
                        .font(.system(size: 10, weight: .medium, design: .serif))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.5))
                .clipShape(Capsule())
                .padding(8)
            }

            // Before/after label
            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.4))
                    .clipShape(Capsule())
                    .padding(6)
            }
        }
    }

    private var statsPanel: some View {
        VStack(spacing: 16) {
            // Duration
            HStack(spacing: 7) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(formattedDuration) studied")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.85))
            }

            // Subject
            HStack(spacing: 7) {
                Circle()
                    .fill(subjectColor)
                    .frame(width: 10, height: 10)
                Text(subjectName)
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.85))
            }

            // Focus metric
            HStack(spacing: 7) {
                Image(systemName: appLeaveCount == 0 ? "checkmark.circle.fill" : "iphone.and.arrow.forward")
                    .font(.system(size: 14))
                    .foregroundStyle(appLeaveCount == 0 ? .green : .white.opacity(0.5))
                Text(appLeaveCount == 0 ? "Perfect focus" : "\(appLeaveCount) app \(appLeaveCount == 1 ? "leave" : "leaves")")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

// MARK: - Custom Sticker Builder

/// Interactive builder for custom sticker layouts with drag-to-reorder, haptic snapping, and presets.
struct CustomStickerBuilderView: View {
    let durationSeconds: Int
    let subjectName: String
    let subjectColor: Color
    let appLeaveCount: Int
    var caption: String = ""
    var studyDescription: String = ""
    var subjectSegments: [SubjectSegment] = []
    var subjectColorResolver: ((String) -> Color)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var config = CustomStickerConfig.load()
    @State private var presets: [CustomStickerConfig.SavedPreset] = []
    @State private var showSaveAlert = false
    @State private var presetName = ""

    private let elementNames = ["Duration", "Subject", "Breakdown", "Focus", "Caption", "Branding"]
    private let elementIcons = ["clock", "book", "list.bullet", "eye", "text.quote", "sparkle"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(FactumTheme.secondaryText)
                }
                Spacer()
                Text("Custom Sticker")
                    .font(.system(size: 16, weight: .light, design: .serif))
                    .foregroundStyle(FactumTheme.primaryText)
                Spacer()
                Button {
                    config.save()
                    Haptics.success()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(FactumTheme.primaryText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Live preview — reacts immediately to config changes
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.10, green: 0.09, blue: 0.08))
                InstagramStickerView(
                    durationSeconds: durationSeconds,
                    subjectName: subjectName,
                    subjectColor: subjectColor,
                    appLeaveCount: appLeaveCount,
                    caption: caption,
                    studyDescription: studyDescription,
                    subjectSegments: subjectSegments,
                    subjectColorResolver: subjectColorResolver,
                    layout: .custom,
                    customConfig: config
                )
                .scaleEffect(0.65)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.2), value: config)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            // Controls
            ScrollView {
                VStack(spacing: 16) {
                    // Drag-to-reorder elements
                    elementReorderSection

                    thinDivider

                    // Style controls (compact rows)
                    styleSection

                    thinDivider

                    // Presets
                    presetSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .background(FactumTheme.background)
        .onAppear { presets = CustomStickerConfig.loadPresets() }
        .alert("Save Preset", isPresented: $showSaveAlert) {
            TextField("Preset name", text: $presetName)
            Button("Save") {
                guard !presetName.isEmpty else { return }
                config.saveAsPreset(name: presetName)
                presets = CustomStickerConfig.loadPresets()
                presetName = ""
                Haptics.success()
            }
            Button("Cancel", role: .cancel) { presetName = "" }
        } message: {
            Text("Name this layout so you can reuse it later.")
        }
    }

    // MARK: - Element Reorder Section

    private var elementReorderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("ELEMENTS", subtitle: "drag to reorder")

            VStack(spacing: 4) {
                ForEach(config.elementOrder.filter { $0 != 2 }, id: \.self) { idx in
                    if idx == 1 && subjectSegments.count > 1 {
                        // Subject + inline breakdown toggle
                        VStack(spacing: 0) {
                            elementRow(idx)
                            if isElementEnabled(idx) {
                                HStack(spacing: 6) {
                                    Spacer().frame(width: 28)
                                    Image(systemName: "list.bullet")
                                        .font(.system(size: 10))
                                        .foregroundStyle(FactumTheme.tertiaryText)
                                    Text("Breakdown")
                                        .font(.system(size: 12, weight: .regular, design: .serif))
                                        .foregroundStyle(FactumTheme.secondaryText)
                                    Spacer()
                                    Toggle("", isOn: $config.showBreakdown)
                                        .labelsHidden()
                                        .scaleEffect(0.7)
                                        .tint(FactumTheme.accent)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 10)
                            }
                        }
                    } else {
                        elementRow(idx)
                    }
                }
            }
        }
    }

    private func elementRow(_ idx: Int) -> some View {
        let filteredOrder = config.elementOrder.filter { $0 != 2 }
        let position = filteredOrder.firstIndex(of: idx) ?? 0
        let isFirst = position == 0
        let isLast = position == filteredOrder.count - 1

        return HStack(spacing: 8) {
            // Move buttons
            VStack(spacing: 0) {
                Button {
                    moveElement(idx, direction: -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isFirst ? FactumTheme.tertiaryText.opacity(0.3) : FactumTheme.secondaryText)
                        .frame(width: 20, height: 14)
                }
                .disabled(isFirst)

                Button {
                    moveElement(idx, direction: 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isLast ? FactumTheme.tertiaryText.opacity(0.3) : FactumTheme.secondaryText)
                        .frame(width: 20, height: 14)
                }
                .disabled(isLast)
            }

            // Icon + name
            Image(systemName: elementIcons[idx])
                .font(.system(size: 11))
                .foregroundStyle(isElementEnabled(idx) ? FactumTheme.primaryText : FactumTheme.tertiaryText)
                .frame(width: 16)
            Text(elementNames[idx])
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(isElementEnabled(idx) ? FactumTheme.primaryText : FactumTheme.tertiaryText)

            Spacer()

            // Toggle
            Toggle("", isOn: elementBinding(idx))
                .labelsHidden()
                .scaleEffect(0.7)
                .tint(FactumTheme.accent)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(FactumTheme.cardBackground)
        )
        .contentShape(Rectangle())
    }

    private func isElementEnabled(_ idx: Int) -> Bool {
        switch idx {
        case 0: return config.showDuration
        case 1: return config.showSubject
        case 3: return config.showFocus
        case 4: return config.showCaption
        case 5: return config.showBranding
        default: return false
        }
    }

    private func elementBinding(_ idx: Int) -> Binding<Bool> {
        switch idx {
        case 0: return Binding(get: { config.showDuration }, set: { config.showDuration = $0; Haptics.light(); config.save() })
        case 1: return Binding(get: { config.showSubject }, set: { config.showSubject = $0; Haptics.light(); config.save() })
        case 3: return Binding(get: { config.showFocus }, set: { config.showFocus = $0; Haptics.light(); config.save() })
        case 4: return Binding(get: { config.showCaption }, set: { config.showCaption = $0; Haptics.light(); config.save() })
        case 5: return Binding(get: { config.showBranding }, set: { config.showBranding = $0; Haptics.light(); config.save() })
        default: return .constant(false)
        }
    }

    private func moveElement(_ idx: Int, direction: Int) {
        guard let currentPos = config.elementOrder.firstIndex(of: idx) else { return }
        let targetPos = currentPos + direction
        guard targetPos >= 0 && targetPos < config.elementOrder.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            config.elementOrder.swapAt(currentPos, targetPos)
        }
        Haptics.selection()
        config.save()
    }

    // MARK: - Style Section

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("STYLE")

            // Layout / Arrangement
            stylePicker("Layout", selection: $config.arrangement, options: CustomStickerConfig.Arrangement.allCases) { $0.rawValue }

            // Background
            stylePicker("Background", selection: $config.backgroundStyle, options: CustomStickerConfig.BackgroundStyle.allCases) { $0.rawValue }

            // Font
            stylePicker("Font", selection: $config.fontStyle, options: CustomStickerConfig.FontStyle.allCases) { $0.rawValue }

            // Alignment (icon buttons)
            HStack {
                Text("Align")
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(FactumTheme.secondaryText)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(CustomStickerConfig.TextAlignment.allCases, id: \.self) { align in
                        let isSelected = config.textAlignment == align
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { config.textAlignment = align }
                            Haptics.selection()
                            config.save()
                        } label: {
                            Image(systemName: alignmentIcon(align))
                                .font(.system(size: 13))
                                .foregroundStyle(isSelected ? FactumTheme.primaryText : FactumTheme.tertiaryText)
                                .frame(width: 34, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? FactumTheme.accent : Color.clear)
                                )
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(FactumTheme.surfaceBackground))
            }

            // Text size
            HStack {
                Text("Size")
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(FactumTheme.secondaryText)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(CustomStickerConfig.TextSize.allCases, id: \.self) { size in
                        let isSelected = config.textSize == size
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { config.textSize = size }
                            Haptics.selection()
                            config.save()
                        } label: {
                            Text(size.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .serif))
                                .foregroundStyle(isSelected ? FactumTheme.primaryText : FactumTheme.tertiaryText)
                                .frame(width: 34, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? FactumTheme.accent : Color.clear)
                                )
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(FactumTheme.surfaceBackground))
            }
        }
    }

    private func alignmentIcon(_ align: CustomStickerConfig.TextAlignment) -> String {
        switch align {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }

    private func stylePicker<T: Hashable>(_ label: String, selection: Binding<T>, options: [T], display: @escaping (T) -> String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(FactumTheme.secondaryText)
            Spacer()
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { opt in
                    let isSelected = selection.wrappedValue == opt
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selection.wrappedValue = opt }
                        Haptics.selection()
                        config.save()
                    } label: {
                        Text(display(opt))
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .serif))
                            .foregroundStyle(isSelected ? FactumTheme.primaryText : FactumTheme.tertiaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? FactumTheme.accent : Color.clear)
                            )
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(FactumTheme.surfaceBackground))
        }
    }

    // MARK: - Presets Section

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("PRESETS")
                Spacer()
                Button {
                    showSaveAlert = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(FactumTheme.secondaryText)
                }
            }

            if presets.isEmpty {
                Text("Save your current layout as a preset to reuse it later.")
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundStyle(FactumTheme.tertiaryText)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets) { preset in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    config = preset.config
                                }
                                config.save()
                                Haptics.medium()
                            } label: {
                                VStack(spacing: 4) {
                                    // Mini preview
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(red: 0.10, green: 0.09, blue: 0.08))
                                        InstagramStickerView(
                                            durationSeconds: durationSeconds,
                                            subjectName: subjectName,
                                            subjectColor: subjectColor,
                                            appLeaveCount: appLeaveCount,
                                            layout: .custom,
                                            customConfig: preset.config
                                        )
                                        .scaleEffect(0.3)
                                        .allowsHitTesting(false)
                                    }
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                config == preset.config ? FactumTheme.primaryText.opacity(0.5) : FactumTheme.separator.opacity(0.3),
                                                lineWidth: config == preset.config ? 1.5 : 0.5
                                            )
                                    )

                                    Text(preset.name)
                                        .font(.system(size: 9, weight: .regular, design: .serif))
                                        .foregroundStyle(FactumTheme.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    CustomStickerConfig.deletePreset(id: preset.id)
                                    presets = CustomStickerConfig.loadPresets()
                                    Haptics.light()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .serif))
                .foregroundStyle(FactumTheme.tertiaryText)
                .tracking(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .regular, design: .serif))
                    .foregroundStyle(FactumTheme.tertiaryText.opacity(0.6))
            }
        }
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(FactumTheme.separator.opacity(0.5))
            .frame(height: 0.5)
    }
}

// MARK: - Sticker Canvas

/// A positioned sticker on the canvas.
struct CanvasStickerItem: Identifiable {
    let id = UUID()
    var layout: StickerLayout
    var position: CGPoint       // center position in canvas coords (360x640)
    var scale: CGFloat = 1.0
}

/// Interactive canvas where users arrange multiple stickers, then export as one image.
struct StickerCanvasView: View {
    let durationSeconds: Int
    let subjectName: String
    let subjectColor: Color
    let appLeaveCount: Int
    var caption: String = ""
    var studyDescription: String = ""
    var subjectSegments: [SubjectSegment] = []
    var subjectColorResolver: ((String) -> Color)? = nil
    var videoURL: URL? = nil
    let onExport: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [CanvasStickerItem] = [
        CanvasStickerItem(layout: .stack, position: CGPoint(x: 180, y: 320))
    ]
    @State private var selectedItemID: UUID? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var pinchBaseScale: CGFloat = 1.0
    @State private var pinchStarted = false
    @State private var dragNearDelete = false

    // Canvas is 360x640 logical (rendered at 3x = 1080x1920)
    private let canvasWidth: CGFloat = 360
    private let canvasHeight: CGFloat = 640

    private let elementLayouts: [StickerLayout] = [.timeOnly, .subjectOnly, .captionOnly, .focusOnly, .appLeaves, .breakdown, .branding]
    private let presetLayouts: [StickerLayout] = [.stack, .card, .bar, .badge, .minimal, .polaroid, .filmStrip, .notebook, .notesClean, .receipt, .stamp, .custom]

    private func addSticker(_ layout: StickerLayout) {
        let offsetX = CGFloat.random(in: -20...20)
        let offsetY = CGFloat.random(in: -20...20)
        let newItem = CanvasStickerItem(
            layout: layout,
            position: CGPoint(x: canvasWidth / 2 + offsetX, y: canvasHeight / 2 + offsetY)
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            items.append(newItem)
            selectedItemID = newItem.id
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(FactumTheme.secondaryText)
                        .frame(width: 32, height: 32)
                }
                Spacer()
                Text("\(items.count) sticker\(items.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(FactumTheme.tertiaryText)
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Canvas
            GeometryReader { geo in
                let scale = min(geo.size.width / canvasWidth, geo.size.height / canvasHeight)
                let scaledW = canvasWidth * scale
                let scaledH = canvasHeight * scale

                ZStack {
                    // Canvas background — dark like Instagram story
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.07))

                    // Center guides (shown while dragging)
                    if isDragging {
                        // Vertical center
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(width: 1, height: scaledH * 0.8)
                        // Horizontal center
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(width: scaledW * 0.8, height: 1)
                    }

                    // Delete zone glow at bottom edge
                    if dragNearDelete {
                        VStack {
                            Spacer()
                            LinearGradient(
                                colors: [.clear, dragNearDelete ? .red.opacity(0.35) : .red.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 60)
                            .overlay(alignment: .bottom) {
                                Image(systemName: dragNearDelete ? "trash.fill" : "trash")
                                    .font(.system(size: dragNearDelete ? 18 : 14))
                                    .foregroundStyle(dragNearDelete ? .red : .white.opacity(0.35))
                                    .padding(.bottom, 10)
                            }
                        }
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.15), value: dragNearDelete)
                    }

                    // Stickers
                    ForEach(items) { item in
                        let isBeingDeleted = dragNearDelete && selectedItemID == item.id
                        stickerView(for: item)
                            .scaleEffect(item.scale * scale * (isBeingDeleted ? 0.85 : 1.0))
                            .opacity(isBeingDeleted ? 0.5 : 1.0)
                            .colorMultiply(isBeingDeleted ? Color(red: 1, green: 0.6, blue: 0.6) : .white)
                            .position(
                                x: item.position.x * scale,
                                y: item.position.y * scale
                            )
                            .animation(.easeInOut(duration: 0.15), value: isBeingDeleted)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        isDragging = true
                                        selectedItemID = item.id
                                        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
                                        var newX = item.position.x + value.translation.width / scale - dragOffset.width / scale
                                        var newY = item.position.y + value.translation.height / scale - dragOffset.height / scale
                                        dragOffset = value.translation

                                        // Gentle snap — only center line, soft threshold
                                        let snapThreshold: CGFloat = 5
                                        let centerX = canvasWidth / 2
                                        let centerY = canvasHeight / 2
                                        if abs(newX - centerX) < snapThreshold {
                                            if abs(items[idx].position.x - centerX) > snapThreshold {
                                                Haptics.selection()
                                            }
                                            newX = centerX
                                        }
                                        if abs(newY - centerY) < snapThreshold {
                                            if abs(items[idx].position.y - centerY) > snapThreshold {
                                                Haptics.selection()
                                            }
                                            newY = centerY
                                        }

                                        items[idx].position = CGPoint(x: newX, y: newY)

                                        // Check if past bottom edge (sticker cut off = delete)
                                        let nearDelete = newY > canvasHeight - 20
                                        if nearDelete != dragNearDelete {
                                            dragNearDelete = nearDelete
                                            if nearDelete { Haptics.medium() }
                                        }
                                    }
                                    .onEnded { _ in
                                        // Delete if in delete zone
                                        if dragNearDelete {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                items.removeAll { $0.id == item.id }
                                                selectedItemID = items.last?.id
                                            }
                                            Haptics.medium()
                                            dragNearDelete = false
                                            isDragging = false
                                            dragOffset = .zero
                                            return
                                        }

                                        isDragging = false
                                        dragOffset = .zero

                                        // Check for combine: if this item overlaps another closely
                                        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
                                        let pos = items[idx].position
                                        for otherIdx in items.indices where otherIdx != idx {
                                            let otherPos = items[otherIdx].position
                                            let dist = hypot(pos.x - otherPos.x, pos.y - otherPos.y)
                                            if dist < 30 {
                                                Haptics.medium()
                                                let midX = (pos.x + otherPos.x) / 2
                                                let midY = (pos.y + otherPos.y) / 2
                                                items[idx].position = CGPoint(x: midX, y: midY - 30)
                                                items[otherIdx].position = CGPoint(x: midX, y: midY + 30)
                                                break
                                            }
                                        }
                                    }
                            )
                            .simultaneousGesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        selectedItemID = item.id
                                        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
                                        if !pinchStarted {
                                            pinchBaseScale = items[idx].scale
                                            pinchStarted = true
                                        }
                                        let newScale = pinchBaseScale * value.magnification
                                        items[idx].scale = min(3.0, max(0.3, newScale))
                                    }
                                    .onEnded { _ in
                                        pinchStarted = false
                                        Haptics.light()
                                    }
                            )
                            .onTapGesture {
                                Haptics.light()
                                selectedItemID = item.id
                                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                                    pinchBaseScale = items[idx].scale
                                }
                            }
                    }

                }
                .frame(width: scaledW, height: scaledH)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Elements — single data pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(elementLayouts, id: \.self) { layout in
                        Button {
                            Haptics.light()
                            addSticker(layout)
                        } label: {
                            Text(layout.label)
                                .font(.system(size: 12, weight: .medium, design: .serif))
                                .foregroundStyle(FactumTheme.primaryText.opacity(0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(FactumTheme.surfaceBackground)
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(FactumTheme.separator.opacity(0.15), lineWidth: 0.5))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // Presets — full layout stickers
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presetLayouts, id: \.self) { layout in
                        Button {
                            Haptics.light()
                            addSticker(layout)
                        } label: {
                            Text(layout.label)
                                .font(.system(size: 12, weight: .regular, design: .serif))
                                .foregroundStyle(FactumTheme.secondaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(FactumTheme.surfaceBackground.opacity(0.6))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(FactumTheme.separator.opacity(0.1), lineWidth: 0.5))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // Share button — prominent and always visible
            Button {
                exportAndShare()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14))
                    Text("Share to Instagram")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                }
                .foregroundStyle(FactumTheme.accentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(FactumTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(FactumTheme.background)
    }

    @ViewBuilder
    private func stickerView(for item: CanvasStickerItem) -> some View {
        InstagramStickerView(
            durationSeconds: durationSeconds,
            subjectName: subjectName,
            subjectColor: subjectColor,
            appLeaveCount: appLeaveCount,
            caption: caption,
            studyDescription: studyDescription,
            subjectSegments: subjectSegments,
            subjectColorResolver: subjectColorResolver,
            layout: item.layout
        )
    }

    @MainActor
    private func exportAndShare() {
        // Render all stickers on a transparent 360x640 canvas at 3x
        let canvasView = ZStack {
            Color.clear
            ForEach(items) { item in
                stickerView(for: item)
                    .scaleEffect(item.scale)
                    .position(item.position)
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)

        let renderer = ImageRenderer(content: canvasView)
        renderer.scale = 3

        guard let uiImage = renderer.uiImage,
              let pngData = uiImage.pngData() else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "instagram-stories://share?source_application=\(bundleID)") else { return }
        guard UIApplication.shared.canOpenURL(url) else { return }

        var pasteboardItem: [String: Any] = [
            "com.instagram.sharedSticker.stickerImage": pngData
        ]

        // Include video as background if available
        if let videoURL, let videoData = try? Data(contentsOf: videoURL) {
            pasteboardItem["com.instagram.sharedSticker.backgroundVideo"] = videoData
        }

        let options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(60 * 5)
        ]
        UIPasteboard.general.setItems([pasteboardItem], options: options)
        UIApplication.shared.open(url)

        Haptics.success()
        dismiss()
    }
}

// MARK: - Story Style Sheet

/// Unified bottom sheet for choosing a sticker layout or full story share.
struct InstagramStoryStyleSheet: View {
    let durationSeconds: Int
    let subjectName: String
    let subjectColor: Color
    let appLeaveCount: Int
    let isLandscape: Bool
    let photo: UIImage?
    let afterPhoto: UIImage?
    let isTimelapse: Bool
    var caption: String = ""
    var studyDescription: String = ""
    var subjectSegments: [SubjectSegment] = []
    var subjectColorResolver: ((String) -> Color)? = nil
    let onShareSticker: (StickerLayout) -> Void
    let onShareFullStory: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedStickerLayout: StickerLayout? = .stack
    @State private var isFullStorySelected = false
    @State private var showCanvas = false

    private func previewScale(for layout: StickerLayout) -> CGFloat {
        switch layout {
        case .stack: return 0.32
        case .card: return 0.35
        case .bar: return 0.30
        case .badge: return 0.45
        case .minimal: return 0.40
        case .timeOnly: return 0.42
        case .subjectOnly: return 0.50
        case .captionOnly: return 0.42
        case .focusOnly: return 0.50
        case .appLeaves: return 0.50
        case .breakdown: return 0.42
        case .branding: return 0.60
        case .notesClean: return 0.34
        case .polaroid: return 0.34
        case .filmStrip: return 0.38
        case .notebook: return 0.34
        case .receipt: return 0.36
        case .stamp: return 0.45
        case .custom: return 0.36
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(FactumTheme.tertiaryText.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 6)

            // Layout picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Sticker layouts
                    ForEach(StickerLayout.allCases) { layout in
                        let isSelected = selectedStickerLayout == layout && !isFullStorySelected
                        Button {
                            if layout == .custom {
                                Haptics.selection()
                                showCanvas = true
                            } else {
                                Haptics.selection()
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedStickerLayout = layout
                                    isFullStorySelected = false
                                }
                            }
                        } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 0.08, green: 0.08, blue: 0.07))
                                    InstagramStickerView(
                                        durationSeconds: durationSeconds,
                                        subjectName: subjectName,
                                        subjectColor: subjectColor,
                                        appLeaveCount: appLeaveCount,
                                        caption: caption,
                                        studyDescription: studyDescription,
                                        subjectSegments: subjectSegments,
                                        subjectColorResolver: subjectColorResolver,
                                        layout: layout
                                    )
                                    .scaleEffect(previewScale(for: layout))
                                    .allowsHitTesting(false)
                                }
                                .frame(width: 80, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            isSelected ? FactumTheme.primaryText.opacity(0.6) : FactumTheme.separator.opacity(0.2),
                                            lineWidth: isSelected ? 1.5 : 0.5
                                        )
                                )
                                .overlay(alignment: .topTrailing) {
                                    if layout == .custom {
                                        Image(systemName: "square.on.square")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.6))
                                            .frame(width: 20, height: 20)
                                            .background(Circle().fill(Color.black.opacity(0.5)))
                                            .padding(3)
                                    }
                                }

                                Text(layout == .custom ? "Canvas" : layout.label)
                                    .font(.system(size: 10, weight: isSelected ? .medium : .regular, design: .serif))
                                    .foregroundStyle(isSelected ? FactumTheme.primaryText : FactumTheme.tertiaryText)
                            }
                        }
                    }

                    // Separator
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(FactumTheme.separator.opacity(0.4))
                        .frame(width: 1, height: 70)
                        .padding(.horizontal, 2)

                    // Full Story option
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isFullStorySelected = true
                            selectedStickerLayout = nil
                        }
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.08, green: 0.08, blue: 0.07))
                                InstagramFullStoryView(
                                    durationSeconds: durationSeconds,
                                    subjectName: subjectName,
                                    subjectColor: subjectColor,
                                    appLeaveCount: appLeaveCount,
                                    isLandscape: isLandscape,
                                    photo: photo,
                                    afterPhoto: afterPhoto,
                                    isTimelapse: isTimelapse
                                )
                                .frame(width: 360, height: 640)
                                .scaleEffect(0.14)
                                .allowsHitTesting(false)
                            }
                            .frame(width: 80, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        isFullStorySelected ? FactumTheme.primaryText.opacity(0.6) : FactumTheme.separator.opacity(0.2),
                                        lineWidth: isFullStorySelected ? 1.5 : 0.5
                                    )
                            )

                            Text("Story")
                                .font(.system(size: 10, weight: isFullStorySelected ? .medium : .regular, design: .serif))
                                .foregroundStyle(isFullStorySelected ? FactumTheme.primaryText : FactumTheme.tertiaryText)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .defaultScrollAnchor(.leading)
            .padding(.bottom, 8)

            // Share button
            Button {
                Haptics.medium()
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if isFullStorySelected {
                        onShareFullStory()
                    } else if let layout = selectedStickerLayout {
                        onShareSticker(layout)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12))
                    Text("Share to Instagram")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                }
                .foregroundStyle(FactumTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .fullScreenCover(isPresented: $showCanvas) {
            StickerCanvasView(
                durationSeconds: durationSeconds,
                subjectName: subjectName,
                subjectColor: subjectColor,
                appLeaveCount: appLeaveCount,
                caption: caption,
                studyDescription: studyDescription,
                subjectSegments: subjectSegments,
                subjectColorResolver: subjectColorResolver,
                onExport: {}
            )
        }
    }
}


