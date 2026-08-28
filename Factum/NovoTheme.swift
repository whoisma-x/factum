//
//  PigeonTheme.swift
//  Pigeon
//
//  Pigeon app theme - warm, imperfect, wabi-sabi
//

import SwiftUI
import Photos
import AVFoundation

extension Font {
    /// Gloucester OS MT Std — the app's sticker font.
    static func gloucester(size: CGFloat) -> Font {
        .custom("GloucesterOSMTStd", size: size)
    }
}

struct PigeonTheme {
    // MARK: - Colors (warm tinted — parchment light, inky dark)
    static let background = Color(light: Color(red: 0.98, green: 0.96, blue: 0.92), dark: Color(red: 0.06, green: 0.06, blue: 0.05))
    static let cardBackground = Color(light: Color(red: 0.95, green: 0.92, blue: 0.87), dark: Color(red: 0.13, green: 0.12, blue: 0.11))
    static let surfaceBackground = Color(light: Color(red: 0.92, green: 0.89, blue: 0.84), dark: Color(red: 0.09, green: 0.08, blue: 0.07))
    static let elevated = Color(light: Color(red: 0.93, green: 0.90, blue: 0.85), dark: Color(red: 0.19, green: 0.18, blue: 0.16))
    static let primaryText = Color(light: Color(red: 0.13, green: 0.10, blue: 0.08), dark: Color(red: 0.93, green: 0.91, blue: 0.88))
    static let secondaryText = Color(light: Color(red: 0.44, green: 0.39, blue: 0.34), dark: Color(red: 0.60, green: 0.58, blue: 0.54))
    static let tertiaryText = Color(light: Color(red: 0.56, green: 0.51, blue: 0.46), dark: Color(red: 0.43, green: 0.41, blue: 0.38))
    static let accent = Color(light: Color(red: 0.84, green: 0.79, blue: 0.72), dark: Color(red: 0.28, green: 0.26, blue: 0.23))
    /// Text on accent-colored backgrounds (buttons, selected segments)
    static let accentText = Color(light: Color(red: 0.13, green: 0.10, blue: 0.08), dark: Color(red: 0.93, green: 0.91, blue: 0.88))
    static let separator = Color(light: Color(red: 0.86, green: 0.81, blue: 0.75), dark: Color(red: 0.22, green: 0.20, blue: 0.18))
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
    static let cornerCard: CGFloat = 16       // Cards, containers
    static let cornerSheet: CGFloat = 24      // Sheets, modals, tab bar

    // MARK: - Shadows (deeper, cinematic depth)
    static let cardShadow: Color = Color(light: Color.black.opacity(0.08), dark: Color.black.opacity(0.4))
    static let cardShadowRadius: CGFloat = 12
    static let cardShadowY: CGFloat = 4

    // MARK: - Font (Gloucester OS MT Std)
    static func font(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .gloucester(size: size)
    }

    static let titleFont = Font.gloucester(size: 32)
    static let headlineFont = Font.gloucester(size: 24)
    static let subheadlineFont = Font.gloucester(size: 19)
    static let bodyFont = Font.gloucester(size: 17)
    static let captionFont = Font.gloucester(size: 15)
    static let smallFont = Font.gloucester(size: 13)
    static let sectionTitleFont = Font.gloucester(size: 17)
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

struct PigeonCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(PigeonTheme.cardBackground)
            .clipShape(OrganicRect(base: 14))
            .shadow(color: PigeonTheme.cardShadow, radius: PigeonTheme.cardShadowRadius, x: 0, y: PigeonTheme.cardShadowY)
    }
}

struct PigeonButtonStyle: ButtonStyle {
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PigeonTheme.subheadlineFont)
            .foregroundStyle(filled ? PigeonTheme.accentText : PigeonTheme.primaryText)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(filled ? PigeonTheme.accent : Color.clear)
            .clipShape(OrganicRect(base: 10))
            .overlay(
                OrganicRect(base: 10)
                    .strokeBorder(PigeonTheme.accent, lineWidth: filled ? 0 : 1.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func pigeonCard() -> some View {
        modifier(PigeonCardModifier())
    }
    
    func pigeonSectionTitle() -> some View {
        modifier(PigeonSectionTitleModifier())
    }
}

struct PigeonSectionTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(PigeonTheme.sectionTitleFont)
            .foregroundStyle(PigeonTheme.tertiaryText)
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
    var thumbnailData: Data? = nil
    var sessionDate: Date = Date()
    /// For animated GIF rendering: if set, shows elapsed time instead of total.
    var elapsedSeconds: Int? = nil
    /// When false, sticker pills have no background fill.
    var showBackground: Bool = true

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

    private var pillBg: Color { showBackground ? Color.black.opacity(0.55) : Color.clear }
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
        case .timeRange: timeRangePill
        case .progressTimer: progressTimerPill
        case .countingTimer: countingTimerPill
        case .progressRing: progressRingPill
        case .liveTicker: liveTickerPill
        case .wallClock: wallClockPill
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
                            .font(.gloucester(size: 18))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    if !studyDescription.isEmpty {
                        Text(studyDescription)
                            .font(.gloucester(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
            }

            Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.horizontal, 8)

            // Big time
            Text(formattedDuration)
                .font(.gloucester(size: 39))
                .foregroundStyle(.white)
            Text("studied")
                .font(.gloucester(size: 15))
                .foregroundStyle(.white.opacity(0.45))

            Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.horizontal, 8)

            // Subject(s)
            if hasMultipleSubjects {
                VStack(spacing: 5) {
                    ForEach(subjectSegments) { seg in
                        HStack(spacing: 6) {
                            Circle().fill(subjectColorResolver?(seg.subject) ?? subjectColor).frame(width: 7, height: 7)
                            Text(seg.subject)
                                .font(.gloucester(size: 13))
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Text(formatSegmentTime(seg.seconds))
                                .font(.gloucester(size: 13))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Circle().fill(subjectColor).frame(width: 8, height: 8)
                    Text(subjectName)
                        .font(.gloucester(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            // Focus
            HStack(spacing: 5) {
                Image(systemName: appLeaveCount == 0 ? "checkmark.circle.fill" : "iphone.and.arrow.forward")
                    .font(.system(size: 11))
                    .foregroundStyle(appLeaveCount == 0 ? .green : .white.opacity(0.45))
                Text(focusText)
                    .font(.gloucester(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 240)
        .overlay(alignment: .bottomTrailing) {
            PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(pillBg))
    }

    // MARK: - Bar (horizontal strip for bottom of story)

    private var barLayout: some View {
        HStack(spacing: 14) {
            // Duration
            VStack(spacing: 2) {
                Text(formattedDuration)
                    .font(.gloucester(size: 22))
                    .foregroundStyle(.white)
                Text("studied")
                    .font(.gloucester(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 28)

            // Subject
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(subjectColor).frame(width: 6, height: 6)
                    Text(subjectName)
                        .font(.gloucester(size: 15))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                Text(focusText)
                    .font(.gloucester(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            if hasCaption {
                Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 28)
                Text(caption)
                    .font(.gloucester(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(pillBg))
    }

    // MARK: - Badge (compact corner badge)

    private var badgeLayout: some View {
        VStack(spacing: 4) {
            Text(formattedDuration)
                .font(.gloucester(size: 27))
                .foregroundStyle(.white)

            HStack(spacing: 4) {
                Circle().fill(subjectColor).frame(width: 6, height: 6)
                Text(subjectName)
                    .font(.gloucester(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            HStack(spacing: 3) {
                Image(systemName: appLeaveCount == 0 ? "checkmark.circle.fill" : "iphone.and.arrow.forward")
                    .font(.system(size: 8))
                    .foregroundStyle(appLeaveCount == 0 ? .green : .white.opacity(0.4))
                Text(focusText)
                    .font(.gloucester(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }

            PigeonIcon(size: 8, color: .white.opacity(glassesOpacity))
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
                .font(.gloucester(size: 43))
                .foregroundStyle(.white)

            HStack(spacing: 5) {
                Circle().fill(subjectColor).frame(width: 7, height: 7)
                Text(subjectName)
                    .font(.gloucester(size: 17))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .overlay(alignment: .bottomTrailing) {
            PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(pillBg))
    }

    // MARK: - Polaroid (classic photo frame with stats below)

    private var polaroidLayout: some View {
        VStack(spacing: 0) {
            // Photo area — shows captured photo or transparent fallback
            Group {
                if let thumbnailData, let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 220, height: 220)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.03))
                        .frame(width: 220, height: 220)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.top, 14)
            .padding(.horizontal, 14)

            // Caption area below photo
            VStack(spacing: 4) {
                if !caption.isEmpty {
                    Text(caption)
                        .font(.gloucester(size: 16))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(formattedDuration)
                            .font(.gloucester(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    HStack(spacing: 4) {
                        Circle().fill(subjectColor).frame(width: 5, height: 5)
                        Text(subjectName)
                            .font(.gloucester(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
        }
        .frame(width: 248)
        .overlay(alignment: .bottomTrailing) {
            PigeonIcon(size: 8, color: .white.opacity(0.15)).padding(8)
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
                    .font(.gloucester(size: 29))
                    .foregroundStyle(.white)
                    .tracking(1)

                Rectangle().fill(.white.opacity(0.1)).frame(height: 1)

                HStack(spacing: 4) {
                    Circle().fill(subjectColor).frame(width: 6, height: 6)
                    Text(subjectName)
                        .font(.gloucester(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }

                if hasCaption {
                    Text(caption)
                        .font(.gloucester(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                HStack(spacing: 3) {
                    Image(systemName: appLeaveCount == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.system(size: 8))
                        .foregroundStyle(appLeaveCount == 0 ? .green.opacity(0.7) : .white.opacity(0.4))
                    Text(focusText)
                        .font(.gloucester(size: 11))
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
            PigeonIcon(size: 8, color: .white.opacity(0.15)).padding(6)
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
                    .font(.gloucester(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(2)
                Spacer()
                PigeonIcon(size: 8, color: .white.opacity(0.15))
            }
            .padding(.bottom, 8)

            // Ruled lines with content
            VStack(alignment: .leading, spacing: 0) {
                notebookLine {
                    HStack(spacing: 6) {
                        Text(formattedDuration)
                            .font(.gloucester(size: 24))
                            .foregroundStyle(.white)
                        Text("studied")
                            .font(.gloucester(size: 15))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                notebookLine {
                    HStack(spacing: 5) {
                        Circle().fill(subjectColor).frame(width: 7, height: 7)
                        Text(subjectName)
                            .font(.gloucester(size: 15))
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
                                    .font(.gloucester(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Text(formatSegmentTime(seg.seconds))
                                    .font(.gloucester(size: 12))
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
                            .font(.gloucester(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                if hasCaption {
                    notebookLine {
                        Text("\"" + caption + "\"")
                            .font(.gloucester(size: 12))
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
                PigeonIcon(size: 14, color: .white.opacity(0.25))
                    .padding(.top, 4)

                Text("STUDY RECEIPT")
                    .font(.gloucester(size: 10))
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
                    .font(.gloucester(size: 9))
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
                .font(.gloucester(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.gloucester(size: 11))
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
                .font(.gloucester(size: 34))
                .foregroundStyle(.white)

            // Subject
            HStack(spacing: 5) {
                Circle().fill(subjectColor).frame(width: 7, height: 7)
                Text(subjectName.uppercased())
                    .font(.gloucester(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(1.5)
            }

            // Branding
            PigeonIcon(size: 10, color: .white.opacity(0.2))
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
                PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity))
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
                        .font(.gloucester(size: 18))
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
                        .font(.gloucester(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .overlay(alignment: .bottomTrailing) {
            PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
        }
        .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    private var durationPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
            Text(formattedDuration)
                .font(.gloucester(size: 34))
                .foregroundStyle(.white)
            Text("studied")
                .font(.gloucester(size: 16))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottomTrailing) {
            PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
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
                                .font(.gloucester(size: 15))
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Text(formatSegmentTime(seg.seconds))
                                .font(.gloucester(size: 15))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .overlay(alignment: .bottomTrailing) {
                    PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
                }
                .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
            } else {
                HStack(spacing: 7) {
                    Circle().fill(subjectColor).frame(width: 9, height: 9)
                    Text(subjectName)
                        .font(.gloucester(size: 17))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .overlay(alignment: .bottomTrailing) {
                    PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
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
                .font(.gloucester(size: 16))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .overlay(alignment: .bottomTrailing) {
            PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
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
                    .font(.gloucester(size: 18))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Text("\(appLeaveCount)")
                    .font(.gloucester(size: 29))
                    .foregroundStyle(.white)
                Text(appLeaveCount == 1 ? "leave" : "leaves")
                    .font(.gloucester(size: 16))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottomTrailing) {
            PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
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
                            .font(.gloucester(size: 15))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Text(formatSegmentTime(seg.seconds))
                            .font(.gloucester(size: 15))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Circle().fill(subjectColor).frame(width: 8, height: 8)
                    Text(subjectName)
                        .font(.gloucester(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text(formattedDuration)
                        .font(.gloucester(size: 16))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .bottomTrailing) {
            PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
        }
        .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    // MARK: - Branding pill (just the logo)

    private var brandingPill: some View {
        PigeonIcon(size: 28, color: .white.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    // MARK: - Time Range (shows start time → end time)

    private var sessionStartTime: Date {
        sessionDate.addingTimeInterval(-Double(durationSeconds))
    }

    /// Current elapsed time for animated rendering, or ~65% for static preview.
    private var currentElapsed: Int {
        elapsedSeconds ?? Int(Double(durationSeconds) * 0.65)
    }

    private var elapsedFraction: CGFloat {
        guard durationSeconds > 0 else { return 1 }
        if elapsedSeconds == nil { return 0.65 } // static preview: show partial fill
        return CGFloat(currentElapsed) / CGFloat(durationSeconds)
    }

    private var formattedElapsed: String {
        let e = currentElapsed
        let h = e / 3600
        let m = (e % 3600) / 60
        let s = e % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    private var currentClockTime: Date {
        sessionStartTime.addingTimeInterval(Double(currentElapsed))
    }

    private func formatClockTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private var timeRangePill: some View {
        HStack(spacing: 6) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatClockTime(sessionStartTime))
                    .font(.gloucester(size: 22))
                    .foregroundStyle(.white)
                Text("start")
                    .font(.gloucester(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

            VStack(spacing: 2) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                Text(formattedElapsed)
                    .font(.gloucester(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(formatClockTime(currentClockTime))
                    .font(.gloucester(size: 22))
                    .foregroundStyle(.white)
                Text(elapsedSeconds != nil ? "now" : "end")
                    .font(.gloucester(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .bottomTrailing) {
            PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(6)
        }
        .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    // MARK: - Progress Timer (visual 0:00 → total with progress bar)

    private var progressTimerPill: some View {
        VStack(spacing: 6) {
            HStack {
                Text(formattedElapsed)
                    .font(.gloucester(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(formattedDuration)
                    .font(.gloucester(size: 13))
                    .foregroundStyle(.white)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.1))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(subjectColor)
                        .frame(width: geo.size.width * elapsedFraction, height: 6)
                }
            }
            .frame(height: 6)

            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                Text("\(formatClockTime(sessionStartTime)) — \(formatClockTime(currentClockTime))")
                    .font(.gloucester(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                PigeonIcon(size: 8, color: .white.opacity(0.15))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 200)
        .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    // MARK: - Counting Timer (large ticking clock-style counter)

    private var countingTimerPill: some View {
        VStack(spacing: 4) {
            Text(formattedElapsed)
                .font(.gloucester(size: 42))
                .foregroundStyle(.white)
                .monospacedDigit()

            HStack(spacing: 6) {
                Circle().fill(subjectColor).frame(width: 6, height: 6)
                Text(subjectName.uppercased())
                    .font(.gloucester(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .overlay(alignment: .bottomTrailing) {
            PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(8)
        }
        .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    // MARK: - Progress Ring (circular progress with time in center)

    private var progressRingPill: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(.white.opacity(0.1), lineWidth: 5)
                .frame(width: 90, height: 90)
            // Progress ring
            Circle()
                .trim(from: 0, to: elapsedFraction)
                .stroke(subjectColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 90, height: 90)
                .rotationEffect(.degrees(-90))

            // Center text
            VStack(spacing: 2) {
                Text(formattedElapsed)
                    .font(.gloucester(size: 16))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(subjectName)
                    .font(.gloucester(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .frame(width: 110, height: 110)
        .overlay(alignment: .bottom) {
            PigeonIcon(size: 8, color: .white.opacity(0.15)).padding(.bottom, 4)
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(pillBg).frame(width: 110, height: 110))
    }

    // MARK: - Live Ticker (scrolling-style subject + time strip)

    private var liveTickerPill: some View {
        HStack(spacing: 10) {
            // Pulsing dot
            Circle()
                .fill(subjectColor)
                .frame(width: 8, height: 8)

            Text(formattedElapsed)
                .font(.gloucester(size: 20))
                .foregroundStyle(.white)
                .monospacedDigit()

            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(width: 1, height: 18)

            Text(subjectName)
                .font(.gloucester(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            PigeonIcon(size: 8, color: .white.opacity(0.2))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(pillBg))
    }

    // MARK: - Wall Clock (large animated real time display)

    private var wallClockPill: some View {
        VStack(spacing: 2) {
            Text(formatClockTime(currentClockTime))
                .font(.gloucester(size: 52))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(formatClockDate(currentClockTime))
                .font(.gloucester(size: 13))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottomTrailing) {
            PigeonIcon(size: glassesSize, color: .white.opacity(glassesOpacity)).padding(8)
        }
        .background(RoundedRectangle(cornerRadius: pillRadius).fill(pillBg))
    }

    private func formatClockDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date).uppercased()
    }

    // MARK: - Notes Clean (notebook without title header)

    private var notesCleanLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            notebookLine {
                HStack(spacing: 6) {
                    Text(formattedDuration)
                        .font(.gloucester(size: 24))
                        .foregroundStyle(.white)
                    Text("studied")
                        .font(.gloucester(size: 15))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            notebookLine {
                HStack(spacing: 5) {
                    Circle().fill(subjectColor).frame(width: 7, height: 7)
                    Text(subjectName)
                        .font(.gloucester(size: 15))
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
                                .font(.gloucester(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Text(formatSegmentTime(seg.seconds))
                                .font(.gloucester(size: 12))
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
                        .font(.gloucester(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if hasCaption {
                notebookLine {
                    Text("\"" + caption + "\"")
                        .font(.gloucester(size: 12))
                        .italic()
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(width: 220)
        .overlay(alignment: .bottomTrailing) {
            PigeonIcon(size: 8, color: .white.opacity(0.15)).padding(8)
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
    case timeRange = "Clock"
    case progressTimer = "Timer"
    case countingTimer = "Counter"
    case progressRing = "Ring"
    case liveTicker = "Ticker"
    case wallClock = "Wall Clock"
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
                    Text("pigeon")
                        .font(.gloucester(size: 15))
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
                            .font(.gloucester(size: 15))
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
                        .font(.gloucester(size: 12))
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
                    .font(.gloucester(size: 12))
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
                    .font(.gloucester(size: 18))
                    .foregroundStyle(.white.opacity(0.85))
            }

            // Subject
            HStack(spacing: 7) {
                Circle()
                    .fill(subjectColor)
                    .frame(width: 10, height: 10)
                Text(subjectName)
                    .font(.gloucester(size: 18))
                    .foregroundStyle(.white.opacity(0.85))
            }

            // Focus metric
            HStack(spacing: 7) {
                Image(systemName: appLeaveCount == 0 ? "checkmark.circle.fill" : "iphone.and.arrow.forward")
                    .font(.system(size: 14))
                    .foregroundStyle(appLeaveCount == 0 ? .green : .white.opacity(0.5))
                Text(appLeaveCount == 0 ? "Perfect focus" : "\(appLeaveCount) app \(appLeaveCount == 1 ? "leave" : "leaves")")
                    .font(.gloucester(size: 18))
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
                        .font(.gloucester(size: 17))
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
                Spacer()
                Text("Custom Sticker")
                    .font(.gloucester(size: 19))
                    .foregroundStyle(PigeonTheme.primaryText)
                Spacer()
                Button {
                    config.save()
                    Haptics.success()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.gloucester(size: 17))
                        .foregroundStyle(PigeonTheme.primaryText)
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
        .background(PigeonTheme.background)
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
                                        .foregroundStyle(PigeonTheme.tertiaryText)
                                    Text("Breakdown")
                                        .font(.gloucester(size: 15))
                                        .foregroundStyle(PigeonTheme.secondaryText)
                                    Spacer()
                                    Toggle("", isOn: $config.showBreakdown)
                                        .labelsHidden()
                                        .scaleEffect(0.7)
                                        .tint(PigeonTheme.accent)
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
                        .foregroundStyle(isFirst ? PigeonTheme.tertiaryText.opacity(0.3) : PigeonTheme.secondaryText)
                        .frame(width: 20, height: 14)
                }
                .disabled(isFirst)

                Button {
                    moveElement(idx, direction: 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isLast ? PigeonTheme.tertiaryText.opacity(0.3) : PigeonTheme.secondaryText)
                        .frame(width: 20, height: 14)
                }
                .disabled(isLast)
            }

            // Icon + name
            Image(systemName: elementIcons[idx])
                .font(.system(size: 11))
                .foregroundStyle(isElementEnabled(idx) ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                .frame(width: 16)
            Text(elementNames[idx])
                .font(.gloucester(size: 16))
                .foregroundStyle(isElementEnabled(idx) ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)

            Spacer()

            // Toggle
            Toggle("", isOn: elementBinding(idx))
                .labelsHidden()
                .scaleEffect(0.7)
                .tint(PigeonTheme.accent)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(PigeonTheme.cardBackground)
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
                    .font(.gloucester(size: 16))
                    .foregroundStyle(PigeonTheme.secondaryText)
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
                                .foregroundStyle(isSelected ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                                .frame(width: 34, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? PigeonTheme.accent : Color.clear)
                                )
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(PigeonTheme.surfaceBackground))
            }

            // Text size
            HStack {
                Text("Size")
                    .font(.gloucester(size: 16))
                    .foregroundStyle(PigeonTheme.secondaryText)
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
                                .font(.gloucester(size: 15))
                                .foregroundStyle(isSelected ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                                .frame(width: 34, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? PigeonTheme.accent : Color.clear)
                                )
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(PigeonTheme.surfaceBackground))
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
                .font(.gloucester(size: 16))
                .foregroundStyle(PigeonTheme.secondaryText)
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
                            .font(.gloucester(size: 13))
                            .foregroundStyle(isSelected ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? PigeonTheme.accent : Color.clear)
                            )
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(PigeonTheme.surfaceBackground))
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
                        .foregroundStyle(PigeonTheme.secondaryText)
                }
            }

            if presets.isEmpty {
                Text("Save your current layout as a preset to reuse it later.")
                    .font(.gloucester(size: 15))
                    .foregroundStyle(PigeonTheme.tertiaryText)
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
                                                config == preset.config ? PigeonTheme.primaryText.opacity(0.5) : PigeonTheme.separator.opacity(0.3),
                                                lineWidth: config == preset.config ? 1.5 : 0.5
                                            )
                                    )

                                    Text(preset.name)
                                        .font(.gloucester(size: 11))
                                        .foregroundStyle(PigeonTheme.secondaryText)
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
                .font(.gloucester(size: 13))
                .foregroundStyle(PigeonTheme.tertiaryText)
                .tracking(1)
            if let subtitle {
                Text(subtitle)
                    .font(.gloucester(size: 12))
                    .foregroundStyle(PigeonTheme.tertiaryText.opacity(0.6))
            }
        }
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(PigeonTheme.separator.opacity(0.5))
            .frame(height: 0.5)
    }
}

// MARK: - Sticker Canvas

/// A positioned sticker on the canvas.
/// A saved story template — persisted arrangement of stickers.
struct SavedStoryTemplate: Codable, Identifiable {
    let id: UUID
    let name: String
    let stickers: [StickerEntry]

    struct StickerEntry: Codable {
        let layout: String  // StickerLayout.rawValue
        let x: CGFloat
        let y: CGFloat
        let scale: CGFloat
    }

    private static let key = "pigeon_saved_story_templates"

    static func loadAll() -> [SavedStoryTemplate] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let templates = try? JSONDecoder().decode([SavedStoryTemplate].self, from: data) else { return [] }
        return templates
    }

    static func saveAll(_ templates: [SavedStoryTemplate]) {
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func add(name: String, items: [CanvasStickerItem]) {
        var all = loadAll()
        let stickers = items.map { StickerEntry(layout: $0.layout.rawValue, x: $0.position.x, y: $0.position.y, scale: $0.scale) }
        all.insert(SavedStoryTemplate(id: UUID(), name: name, stickers: stickers), at: 0)
        saveAll(all)
    }

    static func delete(id: UUID) {
        var all = loadAll()
        all.removeAll { $0.id == id }
        saveAll(all)
    }

    func toCanvasItems() -> [CanvasStickerItem] {
        stickers.compactMap { entry in
            guard let layout = StickerLayout(rawValue: entry.layout) else { return nil }
            return CanvasStickerItem(layout: layout, position: CGPoint(x: entry.x, y: entry.y), scale: entry.scale)
        }
    }
}

struct CanvasStickerItem: Identifiable {
    let id = UUID()
    var layout: StickerLayout
    var position: CGPoint       // center position in canvas coords (360x640)
    var scale: CGFloat = 1.0
    var showBackground: Bool = true
}

/// Approximates CIFilter color grading with SwiftUI modifiers for live preview.
struct ColorGradePreview: ViewModifier {
    let grade: VideoColorGrade

    func body(content: Content) -> some View {
        switch grade {
        case .none:
            content
        case .warm:
            content
                .colorMultiply(Color(red: 1.0, green: 0.95, blue: 0.88))
                .contrast(1.02)
        case .cool:
            content
                .colorMultiply(Color(red: 0.9, green: 0.95, blue: 1.0))
                .contrast(1.02)
        case .vivid:
            content
                .saturation(1.3)
                .contrast(1.08)
                .brightness(0.02)
        case .noir:
            content
                .saturation(0)
                .contrast(1.1)
        case .vintage:
            content
                .saturation(0.7)
                .colorMultiply(Color(red: 1.0, green: 0.96, blue: 0.88))
                .contrast(0.95)
                .brightness(0.03)
        case .fade:
            content
                .saturation(0.75)
                .contrast(0.9)
                .brightness(0.05)
        case .chrome:
            content
                .saturation(1.15)
                .contrast(1.1)
                .colorMultiply(Color(red: 1.0, green: 0.98, blue: 0.95))
        case .mono:
            content
                .saturation(0)
                .contrast(1.05)
                .brightness(0.02)
        }
    }
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
    var thumbnailData: Data? = nil
    var sessionDate: Date = Date()
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
    @State private var showStickerPicker = false
    @State private var pickerPresets: [CustomStickerConfig.SavedPreset] = []
    @State private var savedTemplates: [SavedStoryTemplate] = []
    @State private var showSavePresetAlert = false
    @State private var presetName = ""
    @State private var stickerTint: Color = .white
    @State private var pickerTab: StickerPickerTab = .templates
    @State private var isExporting = false
    @State private var composedVideoURL: URL? = nil
    @State private var showVideoEditor = false
    @State private var selectedColorGrade: VideoColorGrade = .none

    private enum StickerPickerTab: String, CaseIterable {
        case templates = "Templates"
        case animated = "Animated"
        case elements = "Elements"
        case layouts = "Layouts"
    }

    /// A premade story template — places multiple stickers at once.
    private struct StoryTemplate: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let items: [(layout: StickerLayout, position: CGPoint, scale: CGFloat)]
    }

    private let storyTemplates: [StoryTemplate] = [
        // Animated templates first
        StoryTemplate(name: "Timer Story", icon: "timer", items: [
            (.progressRing, CGPoint(x: 180, y: 180), 1.0),
            (.subjectOnly, CGPoint(x: 180, y: 320), 1.0),
            (.branding, CGPoint(x: 180, y: 580), 0.8),
        ]),
        StoryTemplate(name: "Clock", icon: "clock.fill", items: [
            (.wallClock, CGPoint(x: 180, y: 140), 1.0),
            (.stack, CGPoint(x: 180, y: 380), 0.9),
        ]),
        StoryTemplate(name: "Minimal", icon: "minus", items: [
            (.liveTicker, CGPoint(x: 180, y: 560), 1.0),
        ]),
        StoryTemplate(name: "Full Stats", icon: "chart.bar.fill", items: [
            (.countingTimer, CGPoint(x: 180, y: 140), 0.9),
            (.breakdown, CGPoint(x: 180, y: 320), 1.0),
            (.focusOnly, CGPoint(x: 180, y: 470), 1.0),
            (.branding, CGPoint(x: 180, y: 580), 0.8),
        ]),
        StoryTemplate(name: "Polaroid", icon: "photo.fill", items: [
            (.polaroid, CGPoint(x: 180, y: 280), 1.0),
            (.progressTimer, CGPoint(x: 180, y: 530), 0.9),
        ]),
        StoryTemplate(name: "Receipt", icon: "doc.text.fill", items: [
            (.receipt, CGPoint(x: 180, y: 300), 1.0),
        ]),
        StoryTemplate(name: "Notes", icon: "note.text", items: [
            (.notesClean, CGPoint(x: 180, y: 280), 1.0),
            (.timeRange, CGPoint(x: 180, y: 530), 0.9),
        ]),
        StoryTemplate(name: "Badge + Ring", icon: "circle.badge.checkmark.fill", items: [
            (.badge, CGPoint(x: 180, y: 200), 1.0),
            (.progressRing, CGPoint(x: 180, y: 440), 0.85),
            (.branding, CGPoint(x: 180, y: 590), 0.8),
        ]),
    ]

    private func applyTemplate(_ template: StoryTemplate) {
        withAnimation(.easeInOut(duration: 0.25)) {
            items = template.items.map { entry in
                CanvasStickerItem(layout: entry.layout, position: entry.position, scale: entry.scale)
            }
            selectedItemID = items.first?.id
        }
        Haptics.medium()
    }

    // Canvas is 360x640 logical (rendered at 3x = 1080x1920)
    private let canvasWidth: CGFloat = 360
    private let canvasHeight: CGFloat = 640

    private let stickerTintOptions: [(color: Color, label: String)] = [
        (.white, "White"),
        (Color(red: 1.0, green: 0.96, blue: 0.88), "Warm"),
        (Color(red: 0.85, green: 0.92, blue: 1.0), "Cool"),
        (Color(red: 0.75, green: 1.0, blue: 0.82), "Mint"),
        (Color(red: 1.0, green: 0.85, blue: 0.88), "Rose"),
        (Color(red: 1.0, green: 0.92, blue: 0.75), "Peach"),
        (Color(red: 0.92, green: 0.85, blue: 1.0), "Lavender"),
    ]

    private let elementLayouts: [StickerLayout] = [.timeOnly, .subjectOnly, .captionOnly, .focusOnly, .appLeaves, .breakdown, .branding]
    private let animatedElementLayouts: [StickerLayout] = [.progressTimer, .timeRange, .countingTimer, .progressRing, .liveTicker, .wallClock]
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

    // Instagram-style edge margin (proportion of canvas)
    private let edgeMargin: CGFloat = 16

    // Horizontal third snap positions (in canvas coordinates)
    private var hThirdPositions: [CGFloat] {
        [canvasHeight / 3, canvasHeight / 2, canvasHeight * 2 / 3]
    }

    /// Estimated sticker half-size in canvas coordinates for edge-based snapping.
    private func estimatedStickerHalfSize(for layout: StickerLayout, scale: CGFloat) -> (hw: CGFloat, hh: CGFloat) {
        // Approximate rendered widths/heights based on layout type
        let baseW: CGFloat
        let baseH: CGFloat
        switch layout {
        case .timeOnly, .subjectOnly, .focusOnly, .appLeaves, .branding, .liveTicker:
            baseW = 120; baseH = 30
        case .captionOnly, .breakdown, .timeRange, .progressTimer, .countingTimer, .wallClock:
            baseW = 140; baseH = 50
        case .progressRing:
            baseW = 100; baseH = 100
        case .stack, .card, .notesClean, .notebook, .polaroid:
            baseW = 160; baseH = 130
        case .bar, .minimal:
            baseW = 180; baseH = 40
        case .badge, .stamp:
            baseW = 130; baseH = 100
        case .filmStrip:
            baseW = 160; baseH = 100
        case .receipt:
            baseW = 160; baseH = 180
        case .custom:
            baseW = 150; baseH = 120
        }
        return (hw: baseW * scale / 2, hh: baseH * scale / 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Canvas — full bleed, takes all available space
            GeometryReader { geo in
                let scale = min(geo.size.width / canvasWidth, geo.size.height / canvasHeight)
                let scaledW = canvasWidth * scale
                let scaledH = canvasHeight * scale

                ZStack {
                    // Canvas background — thumbnail or dark fallback
                    if let thumbnailData, let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: scaledW, height: scaledH)
                            .clipped()
                            .modifier(ColorGradePreview(grade: selectedColorGrade))
                    } else {
                        Color(red: 0.08, green: 0.08, blue: 0.07)
                    }

                    // Full-frame border — always visible
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(isDragging ? 0.25 : 0.08), lineWidth: isDragging ? 1 : 0.5)
                        .animation(.easeInOut(duration: 0.15), value: isDragging)

                    // Snap guides — only visible when dragging and snapped
                    if isDragging, let sel = items.first(where: { $0.id == selectedItemID }) {
                        let guideRange: CGFloat = 15
                        let half = estimatedStickerHalfSize(for: sel.layout, scale: sel.scale)
                        let leftEdge = sel.position.x - half.hw
                        let rightEdge = sel.position.x + half.hw
                        let topEdge = sel.position.y - half.hh
                        let bottomEdge = sel.position.y + half.hh

                        // Center crosshairs — triggered by sticker center OR edges
                        let centerX = canvasWidth / 2
                        let centerY = canvasHeight / 2
                        if abs(sel.position.x - centerX) < guideRange ||
                           abs(leftEdge - centerX) < guideRange ||
                           abs(rightEdge - centerX) < guideRange {
                            Rectangle()
                                .fill(.white.opacity(0.45))
                                .frame(width: 1, height: scaledH)
                                .position(x: scaledW / 2, y: scaledH / 2)
                        }
                        if abs(sel.position.y - centerY) < guideRange ||
                           abs(topEdge - centerY) < guideRange ||
                           abs(bottomEdge - centerY) < guideRange {
                            Rectangle()
                                .fill(.white.opacity(0.45))
                                .frame(width: scaledW, height: 1)
                                .position(x: scaledW / 2, y: scaledH / 2)
                        }

                        // Frame border highlight — triggered by sticker edge near canvas edge
                        let frameRange: CGFloat = 10
                        let nearFrame = abs(leftEdge) < frameRange ||
                                        abs(rightEdge - canvasWidth) < frameRange ||
                                        abs(topEdge) < frameRange ||
                                        abs(bottomEdge - canvasHeight) < frameRange
                        if nearFrame {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                        }

                        // Horizontal third-line snaps — triggered by center or edges
                        ForEach(hThirdPositions.filter { $0 != canvasHeight / 2 }, id: \.self) { thirdY in
                            if abs(sel.position.y - thirdY) < guideRange ||
                               abs(topEdge - thirdY) < guideRange ||
                               abs(bottomEdge - thirdY) < guideRange {
                                Rectangle()
                                    .fill(.white.opacity(0.25))
                                    .frame(width: scaledW, height: 1)
                                    .position(x: scaledW / 2, y: thirdY * scale)
                            }
                        }
                    }

                    // Delete zone glow at bottom edge
                    if dragNearDelete {
                        VStack {
                            Spacer()
                            LinearGradient(
                                colors: [.clear, .red.opacity(0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 70)
                            .overlay(alignment: .bottom) {
                                VStack(spacing: 4) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 18))
                                    Text("Release to delete")
                                        .font(.gloucester(size: 11))
                                }
                                .foregroundStyle(.red)
                                .padding(.bottom, 12)
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
                            .colorMultiply(isBeingDeleted ? Color(red: 1, green: 0.6, blue: 0.6) : stickerTint)
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

                                        // Edge-aware snapping
                                        let snapThreshold: CGFloat = 5
                                        let centerX = canvasWidth / 2
                                        let centerY = canvasHeight / 2
                                        let half = estimatedStickerHalfSize(for: item.layout, scale: items[idx].scale)

                                        // X-axis: center snap (center or edges) + frame edge snap (edges)
                                        var snappedX = false
                                        // Center: sticker center aligns
                                        if abs(newX - centerX) < snapThreshold {
                                            if abs(items[idx].position.x - centerX) >= snapThreshold { Haptics.selection() }
                                            newX = centerX; snappedX = true
                                        }
                                        // Center: sticker left edge aligns
                                        if !snappedX, abs((newX - half.hw) - centerX) < snapThreshold {
                                            if abs((items[idx].position.x - half.hw) - centerX) >= snapThreshold { Haptics.selection() }
                                            newX = centerX + half.hw; snappedX = true
                                        }
                                        // Center: sticker right edge aligns
                                        if !snappedX, abs((newX + half.hw) - centerX) < snapThreshold {
                                            if abs((items[idx].position.x + half.hw) - centerX) >= snapThreshold { Haptics.selection() }
                                            newX = centerX - half.hw; snappedX = true
                                        }
                                        // Frame: left edge of sticker to left edge of canvas
                                        if !snappedX, abs(newX - half.hw) < snapThreshold {
                                            if abs(items[idx].position.x - half.hw) >= snapThreshold { Haptics.selection() }
                                            newX = half.hw; snappedX = true
                                        }
                                        // Frame: right edge of sticker to right edge of canvas
                                        if !snappedX, abs((newX + half.hw) - canvasWidth) < snapThreshold {
                                            if abs((items[idx].position.x + half.hw) - canvasWidth) >= snapThreshold { Haptics.selection() }
                                            newX = canvasWidth - half.hw; snappedX = true
                                        }

                                        // Y-axis: center + thirds (center or edges) + frame edge (edges)
                                        let snapYGuides: [CGFloat] = [canvasHeight / 3, centerY, canvasHeight * 2 / 3]
                                        var snappedY = false
                                        for target in snapYGuides {
                                            // Sticker center
                                            if abs(newY - target) < snapThreshold {
                                                if abs(items[idx].position.y - target) >= snapThreshold { Haptics.selection() }
                                                newY = target; snappedY = true; break
                                            }
                                            // Sticker top edge
                                            if abs((newY - half.hh) - target) < snapThreshold {
                                                if abs((items[idx].position.y - half.hh) - target) >= snapThreshold { Haptics.selection() }
                                                newY = target + half.hh; snappedY = true; break
                                            }
                                            // Sticker bottom edge
                                            if abs((newY + half.hh) - target) < snapThreshold {
                                                if abs((items[idx].position.y + half.hh) - target) >= snapThreshold { Haptics.selection() }
                                                newY = target - half.hh; snappedY = true; break
                                            }
                                        }
                                        // Frame: top edge
                                        if !snappedY, abs(newY - half.hh) < snapThreshold {
                                            if abs(items[idx].position.y - half.hh) >= snapThreshold { Haptics.selection() }
                                            newY = half.hh; snappedY = true
                                        }
                                        // Frame: bottom edge
                                        if !snappedY, abs((newY + half.hh) - canvasHeight) < snapThreshold {
                                            if abs((items[idx].position.y + half.hh) - canvasHeight) >= snapThreshold { Haptics.selection() }
                                            newY = canvasHeight - half.hh
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
                    }

                }
                .frame(width: scaledW, height: scaledH)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { location in
                    var bestID: UUID?
                    var bestDist: CGFloat = .greatestFiniteMagnitude
                    for item in items {
                        let dx = item.position.x * scale - location.x
                        let dy = item.position.y * scale - location.y
                        let dist = hypot(dx, dy)
                        if dist < bestDist {
                            bestDist = dist
                            bestID = item.id
                        }
                    }
                    if let id = bestID, bestDist < 80 * scale {
                        if selectedItemID == id {
                            // Tap again on selected sticker → toggle background
                            if let idx = items.firstIndex(where: { $0.id == id }) {
                                Haptics.selection()
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    items[idx].showBackground.toggle()
                                }
                            }
                        } else {
                            Haptics.light()
                            selectedItemID = id
                            if let idx = items.firstIndex(where: { $0.id == id }) {
                                pinchBaseScale = items[idx].scale
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 8)

            // Bottom toolbar — compact, Instagram-style
            VStack(spacing: 10) {
                // Tint + sticker count row
                HStack(spacing: 0) {
                    // Tint palette
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(stickerTintOptions.enumerated()), id: \.offset) { _, option in
                                Button {
                                    Haptics.selection()
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        stickerTint = option.color
                                    }
                                } label: {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Circle()
                                                .stroke(stickerTint == option.color ? Color.white : Color.clear, lineWidth: 1.5)
                                                .frame(width: 28, height: 28)
                                        )
                                }
                            }
                        }
                        .padding(.leading, 16)
                    }

                    Spacer()

                    // Sticker count badge
                    Text("\(items.count)")
                        .font(.gloucester(size: 13))
                        .foregroundStyle(PigeonTheme.tertiaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PigeonTheme.surfaceBackground.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(.trailing, 16)
                }

                // Color grade picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(VideoColorGrade.allCases) { grade in
                            Button {
                                Haptics.selection()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedColorGrade = grade
                                }
                            } label: {
                                Text(grade.rawValue)
                                    .font(.gloucester(size: 12))
                                    .foregroundStyle(selectedColorGrade == grade ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        selectedColorGrade == grade
                                            ? PigeonTheme.surfaceBackground
                                            : Color.clear
                                    )
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                selectedColorGrade == grade ? PigeonTheme.separator.opacity(0.3) : Color.clear,
                                                lineWidth: 0.5
                                            )
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Action buttons row
                HStack(spacing: 10) {
                    // Close
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .frame(width: 44, height: 44)
                            .background(PigeonTheme.surfaceBackground)
                            .clipShape(Circle())
                    }

                    // Add stickers
                    Button {
                        Haptics.light()
                        withAnimation(.easeOut(duration: 0.25)) { showStickerPicker = true }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Stickers")
                                .font(.gloucester(size: 16))
                        }
                        .foregroundStyle(PigeonTheme.primaryText)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(PigeonTheme.surfaceBackground)
                        .clipShape(Capsule())
                    }

                    Spacer()

                    // Share button
                    Button {
                        exportAndShare()
                    } label: {
                        HStack(spacing: 6) {
                            if isExporting {
                                ProgressView()
                                    .tint(PigeonTheme.accentText)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 13))
                            }
                            Text(isExporting ? "Exporting…" : "Instagram")
                                .font(.gloucester(size: 16))
                        }
                        .foregroundStyle(PigeonTheme.accentText)
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .background(isExporting ? PigeonTheme.accent.opacity(0.6) : PigeonTheme.accent)
                        .clipShape(Capsule())
                    }
                    .disabled(isExporting)
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(PigeonTheme.background)
        .overlay {
            if showStickerPicker {
                stickerPickerOverlay
            }
        }
    }

    // MARK: - Inline Sticker Picker Overlay

    private func pickerStickerPreview(for layout: StickerLayout) -> some View {
        InstagramStickerView(
            durationSeconds: durationSeconds,
            subjectName: subjectName,
            subjectColor: subjectColor,
            appLeaveCount: appLeaveCount,
            caption: caption,
            studyDescription: studyDescription,
            subjectSegments: subjectSegments,
            subjectColorResolver: subjectColorResolver,
            layout: layout,
            thumbnailData: thumbnailData,
            sessionDate: sessionDate
        )
    }

    private func pickerPreviewScale(for layout: StickerLayout) -> CGFloat {
        switch layout {
        case .stack: return 0.48
        case .card: return 0.50
        case .bar: return 0.46
        case .badge: return 0.60
        case .minimal: return 0.55
        case .timeOnly: return 0.75
        case .subjectOnly: return 0.80
        case .captionOnly: return 0.70
        case .focusOnly: return 0.80
        case .appLeaves: return 0.80
        case .breakdown: return 0.65
        case .branding: return 1.0
        case .timeRange: return 0.70
        case .progressTimer: return 0.65
        case .countingTimer: return 0.55
        case .progressRing: return 0.55
        case .liveTicker: return 0.70
        case .wallClock: return 0.45
        case .notesClean: return 0.48
        case .polaroid: return 0.48
        case .filmStrip: return 0.52
        case .notebook: return 0.48
        case .receipt: return 0.50
        case .stamp: return 0.60
        case .custom: return 0.50
        }
    }

    private func pickerCellHeight(for layout: StickerLayout) -> CGFloat {
        switch layout {
        case .timeOnly, .subjectOnly, .focusOnly, .appLeaves, .branding, .liveTicker:
            return 50
        case .captionOnly, .breakdown, .timeRange, .progressTimer, .countingTimer, .wallClock:
            return 70
        case .progressRing:
            return 80
        default:
            return 140
        }
    }

    private func pickerCell(for layout: StickerLayout) -> some View {
        Button {
            addSticker(layout)
            withAnimation(.easeOut(duration: 0.2)) { showStickerPicker = false }
        } label: {
            VStack(spacing: 4) {
                pickerStickerPreview(for: layout)
                    .scaleEffect(pickerPreviewScale(for: layout))
                    .frame(height: pickerCellHeight(for: layout))
                    .frame(maxWidth: .infinity)
                    .clipped()

                Text(layout.label)
                    .font(.gloucester(size: 12))
                    .foregroundStyle(PigeonTheme.tertiaryText)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var stickerPickerOverlay: some View {
        ZStack(alignment: .bottom) {
            // Dimmed backdrop — tap to dismiss
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { showStickerPicker = false }
                }

            // Picker panel
            VStack(spacing: 0) {
                // Handle + close
                HStack {
                    Text("Add Sticker")
                        .font(.gloucester(size: 19))
                        .foregroundStyle(PigeonTheme.primaryText)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showStickerPicker = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(PigeonTheme.tertiaryText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

                // Segmented tab bar
                HStack(spacing: 0) {
                    ForEach(StickerPickerTab.allCases, id: \.self) { tab in
                        Button {
                            Haptics.selection()
                            withAnimation(.easeInOut(duration: 0.2)) { pickerTab = tab }
                        } label: {
                            Text(tab.rawValue)
                                .font(.gloucester(size: 16))
                                .foregroundStyle(pickerTab == tab ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    pickerTab == tab
                                        ? PigeonTheme.surfaceBackground
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 0) {
                        switch pickerTab {
                        case .templates:
                            // Premade story arrangements — one-tap to place
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                ForEach(storyTemplates) { template in
                                    Button {
                                        applyTemplate(template)
                                        withAnimation(.easeOut(duration: 0.2)) { showStickerPicker = false }
                                    } label: {
                                        templatePreviewCell(name: template.name, icon: template.icon, entries: template.items.map { (layout: $0.layout, x: $0.position.x, y: $0.position.y, scale: $0.scale) })
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Saved templates
                            if !savedTemplates.isEmpty {
                                HStack {
                                    Text("Saved")
                                        .font(.gloucester(size: 14))
                                        .foregroundStyle(PigeonTheme.tertiaryText)
                                    Spacer()
                                }
                                .padding(.top, 16)
                                .padding(.bottom, 4)

                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                    ForEach(savedTemplates) { saved in
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                items = saved.toCanvasItems()
                                                selectedItemID = items.first?.id
                                            }
                                            Haptics.medium()
                                            withAnimation(.easeOut(duration: 0.2)) { showStickerPicker = false }
                                        } label: {
                                            templatePreviewCell(
                                                name: saved.name, icon: "bookmark.fill",
                                                entries: saved.stickers.compactMap { entry in
                                                    guard let layout = StickerLayout(rawValue: entry.layout) else { return nil }
                                                    return (layout: layout, x: entry.x, y: entry.y, scale: entry.scale)
                                                }
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                SavedStoryTemplate.delete(id: saved.id)
                                                savedTemplates = SavedStoryTemplate.loadAll()
                                                Haptics.light()
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }

                            // Save current arrangement
                            if !items.isEmpty {
                                Divider().padding(.vertical, 12)

                                Button {
                                    showSavePresetAlert = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.and.arrow.down")
                                            .font(.system(size: 12))
                                        Text("Save current layout")
                                            .font(.gloucester(size: 14))
                                    }
                                    .foregroundStyle(PigeonTheme.secondaryText)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .background(PigeonTheme.surfaceBackground.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }

                        case .animated:
                            // Animated stickers — these change over video time
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                ForEach(animatedElementLayouts, id: \.self) { layout in
                                    pickerCell(for: layout)
                                }
                            }

                            // Animated badge
                            HStack(spacing: 4) {
                                Image(systemName: "film")
                                    .font(.system(size: 10))
                                Text("These stickers animate in the exported video")
                                    .font(.gloucester(size: 11))
                            }
                            .foregroundStyle(PigeonTheme.tertiaryText.opacity(0.6))
                            .padding(.top, 12)

                        case .elements:
                            // Compact chip-style element pills — 4 columns
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                                ForEach(elementLayouts, id: \.self) { layout in
                                    Button {
                                        addSticker(layout)
                                        withAnimation(.easeOut(duration: 0.2)) { showStickerPicker = false }
                                    } label: {
                                        Text(layout.label)
                                            .font(.gloucester(size: 13))
                                            .foregroundStyle(PigeonTheme.primaryText)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(PigeonTheme.surfaceBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(PigeonTheme.separator.opacity(0.15), lineWidth: 0.5)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                        case .layouts:
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                                ForEach(presetLayouts, id: \.self) { layout in
                                    if layout != .custom {
                                        pickerCell(for: layout)
                                    }
                                }

                                // Custom / Build your own
                                Button {
                                    addSticker(.custom)
                                    withAnimation(.easeOut(duration: 0.2)) { showStickerPicker = false }
                                } label: {
                                    VStack(spacing: 4) {
                                        VStack(spacing: 4) {
                                            Image(systemName: "slider.horizontal.3")
                                                .font(.system(size: 16))
                                                .foregroundStyle(PigeonTheme.secondaryText.opacity(0.5))
                                            Text("Build your own")
                                                .font(.gloucester(size: 12))
                                                .foregroundStyle(PigeonTheme.tertiaryText)
                                        }
                                        .frame(height: 140)
                                        .frame(maxWidth: .infinity)
                                        .background(PigeonTheme.surfaceBackground.opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                        Text("Custom")
                                            .font(.gloucester(size: 12))
                                            .foregroundStyle(PigeonTheme.tertiaryText)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.65)
            .background(PigeonTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 20, y: -5)
            .padding(.bottom, -34)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .alert("Save Template", isPresented: $showSavePresetAlert) {
                TextField("Template name", text: $presetName)
                Button("Save") {
                    SavedStoryTemplate.add(name: presetName.isEmpty ? "My Template" : presetName, items: items)
                    savedTemplates = SavedStoryTemplate.loadAll()
                    presetName = ""
                    Haptics.light()
                }
                Button("Cancel", role: .cancel) { presetName = "" }
            }
        }
        .onAppear {
            pickerPresets = CustomStickerConfig.loadPresets()
            savedTemplates = SavedStoryTemplate.loadAll()
        }
    }

    /// Shared preview cell for template grid items.
    private func templatePreviewCell(name: String, icon: String, entries: [(layout: StickerLayout, x: CGFloat, y: CGFloat, scale: CGFloat)]) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.12))
                    .aspectRatio(9.0/16.0, contentMode: .fit)

                GeometryReader { geo in
                    let previewScale = geo.size.width / canvasWidth
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(entry.layout == .branding ? .white.opacity(0.15) : .white.opacity(0.3))
                            .frame(
                                width: max(24, 50 * entry.scale) * previewScale,
                                height: max(10, 20 * entry.scale) * previewScale
                            )
                            .position(
                                x: entry.x * previewScale,
                                y: entry.y * previewScale
                            )
                    }
                }
            }
            .frame(height: 100)

            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(name)
                    .font(.gloucester(size: 12))
                    .lineLimit(1)
            }
            .foregroundStyle(PigeonTheme.secondaryText)
        }
    }

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
            layout: item.layout,
            thumbnailData: thumbnailData,
            sessionDate: sessionDate,
            showBackground: item.showBackground
        )
    }

    private func stickerView(for item: CanvasStickerItem, elapsedSeconds: Int) -> some View {
        InstagramStickerView(
            durationSeconds: durationSeconds,
            subjectName: subjectName,
            subjectColor: subjectColor,
            appLeaveCount: appLeaveCount,
            caption: caption,
            studyDescription: studyDescription,
            subjectSegments: subjectSegments,
            subjectColorResolver: subjectColorResolver,
            layout: item.layout,
            thumbnailData: thumbnailData,
            sessionDate: sessionDate,
            elapsedSeconds: elapsedSeconds,
            showBackground: item.showBackground
        )
    }

    private static let animatedLayouts: Set<StickerLayout> = [.progressTimer, .timeRange, .countingTimer, .progressRing, .liveTicker, .wallClock]

    private var hasAnimatedStickers: Bool {
        items.contains { Self.animatedLayouts.contains($0.layout) }
    }

    /// Renders a sticker overlay image at a given elapsed time.
    @MainActor
    private func renderStickerOverlay(elapsedSeconds: Int, size: CGSize) -> UIImage? {
        let canvasView = ZStack {
            Color.clear
            ForEach(items) { item in
                if Self.animatedLayouts.contains(item.layout) {
                    stickerView(for: item, elapsedSeconds: elapsedSeconds)
                        .colorMultiply(stickerTint)
                        .scaleEffect(item.scale)
                        .position(item.position)
                } else {
                    stickerView(for: item)
                        .colorMultiply(stickerTint)
                        .scaleEffect(item.scale)
                        .position(item.position)
                }
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)

        let renderer = ImageRenderer(content: canvasView)
        renderer.scale = size.width / canvasWidth
        return renderer.uiImage
    }

    /// Applies a CIFilter color grade to a video, writing to a temp file.
    private func applyColorGrade(_ grade: VideoColorGrade, to videoURL: URL) async -> URL? {
        guard grade != .none, let filterName = grade.ciFilterName else { return nil }
        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        let duration = try? await asset.load(.duration)
        guard let duration else { return nil }

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try? compVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        // Copy audio
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compAudio.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        let ciFilter = CIFilter(name: filterName)!
        grade.configure(ciFilter)
        let handler: @Sendable (AVAsynchronousCIImageFilteringRequest) -> Void = { request in
            ciFilter.setValue(request.sourceImage, forKey: kCIInputImageKey)
            if let output = ciFilter.outputImage {
                request.finish(with: output, context: nil)
            } else {
                request.finish(with: request.sourceImage, context: nil)
            }
        }
        guard let videoComposition = try? AVVideoComposition(asset: composition, applyingCIFiltersWithHandler: handler) else { return nil }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pigeon_graded_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition
        await exporter.export()
        return exporter.status == .completed ? outputURL : nil
    }

    /// Burns stickers (including animated timer) into the video, writes to a temp file.
    @MainActor
    private func burnStickersIntoVideo(videoURL: URL) async -> URL? {
        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        let duration = try? await asset.load(.duration)
        let naturalSize = try? await videoTrack.load(.naturalSize)
        let transform = try? await videoTrack.load(.preferredTransform)
        guard let duration, let naturalSize, let transform else { return nil }

        // Compute actual video dimensions (accounting for rotation)
        let videoSize: CGSize
        let isRotated = abs(transform.b) == 1.0
        if isRotated {
            videoSize = CGSize(width: naturalSize.height, height: naturalSize.width)
        } else {
            videoSize = naturalSize
        }

        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else { return nil }

        // Set up composition
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try? compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        // Copy audio if present
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        // Pre-render sticker overlays — one per unique session second.
        // The session lasted `durationSeconds` real seconds and the timelapse
        // video is `totalSeconds` long.  Map linearly:
        //   videoTime = (sessionElapsed / durationSeconds) * totalSeconds
        // Only render at each unique sessionElapsed value to avoid OOM.
        // CAKeyframeAnimation with .discrete mode holds each image until
        // the next keyTime, so we only need one image per visual change.
        var overlayImages: [CGImage] = []
        var keyTimes: [NSNumber] = []

        // Determine which session seconds actually appear in the video
        let fps: Double = 30.0
        let totalFrames = Int(ceil(totalSeconds * fps))
        var uniqueSeconds: [Int] = []
        var lastSec = -1
        for frame in 0...totalFrames {
            let fraction = Double(frame) / Double(totalFrames)
            let sessionElapsed = min(Int(fraction * Double(durationSeconds)), durationSeconds)
            if sessionElapsed != lastSec {
                uniqueSeconds.append(sessionElapsed)
                lastSec = sessionElapsed
            }
        }

        // Render only unique seconds — much fewer images in memory
        // Limit to at most 300 keyframes to keep memory bounded (~2.4GB max)
        let maxKeyframes = 300
        var renderSeconds = uniqueSeconds
        if renderSeconds.count > maxKeyframes {
            let step = Double(renderSeconds.count) / Double(maxKeyframes)
            var sampled: [Int] = []
            for i in 0..<maxKeyframes {
                sampled.append(renderSeconds[Int(Double(i) * step)])
            }
            // Always include the last second
            if sampled.last != renderSeconds.last {
                sampled.append(renderSeconds.last!)
            }
            renderSeconds = sampled
        }

        // Use an autoreleasepool to release intermediate UIImages promptly
        for (_, sec) in renderSeconds.enumerated() {
            autoreleasepool {
                if let overlay = renderStickerOverlay(elapsedSeconds: sec, size: videoSize),
                   let cg = overlay.cgImage {
                    overlayImages.append(cg)
                    // Compute the video-time fraction for this session second
                    let videoFraction = Double(sec) / Double(max(1, durationSeconds))
                    keyTimes.append(NSNumber(value: min(videoFraction, 1.0)))
                }
            }
        }

        guard !overlayImages.isEmpty else { return nil }

        // Ensure keyTimes starts at 0 and ends at 1
        if let first = keyTimes.first, first.doubleValue > 0 {
            keyTimes[0] = NSNumber(value: 0)
        }
        if let last = keyTimes.last, last.doubleValue < 1.0 {
            keyTimes[keyTimes.count - 1] = NSNumber(value: 1.0)
        }

        // Use AVVideoComposition with handler to overlay stickers per-frame
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = videoSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30fps output

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Use Core Animation for overlay
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: videoSize)

        // Create keyframe animation with sticker images
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = overlayImages
        animation.keyTimes = keyTimes
        animation.duration = totalSeconds
        animation.repeatCount = 1
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.calculationMode = .discrete
        overlayLayer.add(animation, forKey: "stickerAnimation")

        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        // Export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pigeon_sticker_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition

        await exporter.export()
        return exporter.status == .completed ? outputURL : nil
    }

    /// Crops a UIImage to its non-transparent content with padding.
    private func cropToContent(_ image: UIImage, padding: CGFloat = 20) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height

        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return image }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        var minX = width, minY = height, maxX = 0, maxY = 0

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                // Alpha channel — last byte in RGBA or first in ARGB
                let alpha: UInt8
                if cgImage.alphaInfo == .premultipliedFirst || cgImage.alphaInfo == .first || cgImage.alphaInfo == .noneSkipFirst {
                    alpha = ptr[offset]
                } else {
                    alpha = ptr[offset + bytesPerPixel - 1]
                }
                if alpha > 10 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard maxX > minX, maxY > minY else { return image }

        let scale = image.scale
        let pad = Int(padding * scale)
        let cropX = max(0, minX - pad)
        let cropY = max(0, minY - pad)
        let cropW = min(width - cropX, (maxX - minX) + 2 * pad)
        let cropH = min(height - cropY, (maxY - minY) + 2 * pad)
        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)

        guard let cropped = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped, scale: scale, orientation: image.imageOrientation)
    }

    @MainActor
    private func exportAndShare() {
        isExporting = true
        Task {
            // Apply color grade to the video first, if selected
            var gradedVideoURL = videoURL
            if selectedColorGrade != .none, let sourceVideo = videoURL {
                if let graded = await applyColorGrade(selectedColorGrade, to: sourceVideo) {
                    gradedVideoURL = graded
                }
            }

            // If animated stickers + video: burn stickers into video
            if hasAnimatedStickers, let url = gradedVideoURL {
                if let outputURL = await burnStickersIntoVideo(videoURL: url) {
                    composedVideoURL = outputURL
                    isExporting = false
                    shareVideoToInstagram(videoURL: outputURL)
                } else {
                    isExporting = false
                    shareStaticStickerToInstagram(backgroundVideoURL: gradedVideoURL)
                }
            } else {
                isExporting = false
                shareStaticStickerToInstagram(backgroundVideoURL: gradedVideoURL)
            }
        }
    }

    @MainActor
    private func shareStaticStickerToInstagram(backgroundVideoURL: URL? = nil) {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "instagram-stories://share?source_application=\(bundleID)") else { return }
        guard UIApplication.shared.canOpenURL(url) else { return }

        let canvasView = ZStack {
            Color.clear
            ForEach(items) { item in
                stickerView(for: item)
                    .colorMultiply(stickerTint)
                    .scaleEffect(item.scale)
                    .position(item.position)
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)

        let renderer = ImageRenderer(content: canvasView)
        renderer.scale = 3

        guard let uiImage = renderer.uiImage else { return }
        let cropped = cropToContent(uiImage)
        guard let pngData = cropped.pngData() else { return }

        var pasteboardItem: [String: Any] = [
            "com.instagram.sharedSticker.stickerImage": pngData
        ]

        let bgVideo = backgroundVideoURL ?? videoURL
        if let bgVideo, let videoData = try? Data(contentsOf: bgVideo) {
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

    @MainActor
    private func shareVideoToInstagram(videoURL: URL) {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "instagram-stories://share?source_application=\(bundleID)") else { return }
        guard UIApplication.shared.canOpenURL(url) else { return }
        guard let videoData = try? Data(contentsOf: videoURL) else { return }

        let pasteboardItem: [String: Any] = [
            "com.instagram.sharedSticker.backgroundVideo": videoData
        ]

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
    var date: Date = Date()
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
        case .timeRange: return 0.42
        case .progressTimer: return 0.40
        case .countingTimer: return 0.38
        case .progressRing: return 0.38
        case .liveTicker: return 0.45
        case .wallClock: return 0.32
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
                .fill(PigeonTheme.tertiaryText.opacity(0.4))
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
                                            isSelected ? PigeonTheme.primaryText.opacity(0.6) : PigeonTheme.separator.opacity(0.2),
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
                                    .font(.gloucester(size: 12))
                                    .foregroundStyle(isSelected ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
                            }
                        }
                    }

                    // Separator
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(PigeonTheme.separator.opacity(0.4))
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
                                        isFullStorySelected ? PigeonTheme.primaryText.opacity(0.6) : PigeonTheme.separator.opacity(0.2),
                                        lineWidth: isFullStorySelected ? 1.5 : 0.5
                                    )
                            )

                            Text("Story")
                                .font(.gloucester(size: 12))
                                .foregroundStyle(isFullStorySelected ? PigeonTheme.primaryText : PigeonTheme.tertiaryText)
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
                        .font(.gloucester(size: 17))
                }
                .foregroundStyle(PigeonTheme.primaryText)
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
                sessionDate: date,
                onExport: {}
            )
        }
    }
}

// MARK: - Photo Filter

enum PhotoFilter: String, CaseIterable, Identifiable {
    case none = "None"
    case warm = "Warm"
    case cool = "Cool"
    case vintage = "Vintage"
    case bw = "B&W"
    case sepia = "Sepia"
    case highContrast = "Contrast"
    case fade = "Fade"

    var id: String { rawValue }

    @ViewBuilder
    func apply<V: View>(to view: V) -> some View {
        switch self {
        case .none:
            view
        case .warm:
            view.colorMultiply(Color(red: 1.0, green: 0.94, blue: 0.87)).contrast(1.05)
        case .cool:
            view.colorMultiply(Color(red: 0.88, green: 0.93, blue: 1.0)).contrast(1.03)
        case .vintage:
            view.colorMultiply(Color(red: 1.0, green: 0.95, blue: 0.82)).saturation(0.7).contrast(1.1)
        case .bw:
            view.saturation(0).contrast(1.1)
        case .sepia:
            view.saturation(0).colorMultiply(Color(red: 0.94, green: 0.82, blue: 0.64)).contrast(1.05)
        case .highContrast:
            view.contrast(1.35).saturation(1.15)
        case .fade:
            view.saturation(0.6).contrast(0.85).brightness(0.06)
        }
    }
}

// MARK: - Timelapse Export Overlay View

/// Unified export/share screen. Shows the timelapse thumbnail with a
/// poster-style stats overlay. The user can toggle overlay elements,
/// then save, share, or send to Instagram Story — all from one place.
struct TimelapseExportView: View {
    let thumbnailData: Data?
    let videoURL: URL?
    let durationSeconds: Int
    let subjectName: String
    let subjectColor: Color
    let date: Date
    let caption: String
    let appLeaveCount: Int
    var subjectSegments: [SubjectSegment] = []
    var subjectColorResolver: ((String) -> Color)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showDarkOverlay = true
    @State private var showBranding = true
    @State private var showSubject = true
    @State private var showDate = true
    @State private var isSaving = false
    @State private var savedToPhotos = false
    @State private var showShareSheet = false
    @State private var renderedShareImage: UIImage? = nil
    @State private var showInstagramNotInstalled = false
    @State private var showStickerCanvas = false
    @State private var selectedFilter: PhotoFilter = .none

    // Canvas logical size (rendered at 3x = 1080×1920)
    private let canvasWidth: CGFloat = 360
    private let canvasHeight: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                }
                Spacer()
                Text("EXPORT")
                    .font(.gloucester(size: 15))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Preview
            GeometryReader { geo in
                let scale = min(
                    (geo.size.width - 32) / canvasWidth,
                    (geo.size.height - 8) / canvasHeight
                )
                let scaledW = canvasWidth * scale
                let scaledH = canvasHeight * scale

                exportCanvas
                    .frame(width: canvasWidth, height: canvasHeight)
                    .scaleEffect(scale)
                    .frame(width: scaledW, height: scaledH)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Options + actions
            VStack(spacing: 14) {
                // Toggle chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        exportChip("Background", isOn: $showDarkOverlay, icon: "circle.lefthalf.filled")
                        exportChip("Subject", isOn: $showSubject, icon: "book.fill")
                        exportChip("Date", isOn: $showDate, icon: "calendar")
                        exportChip("Branding", isOn: $showBranding, icon: "textformat")
                    }
                    .padding(.horizontal, 20)
                }

                // Filter picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(PhotoFilter.allCases) { filter in
                            Button {
                                Haptics.selection()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedFilter = filter
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Group {
                                        if let thumbnailData, let uiImage = UIImage(data: thumbnailData) {
                                            filter.apply(to:
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            )
                                            .frame(width: 44, height: 44)
                                            .clipped()
                                        } else {
                                            filter.apply(to:
                                                Color(red: 0.3, green: 0.25, blue: 0.2)
                                            )
                                            .frame(width: 44, height: 44)
                                        }
                                    }
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(selectedFilter == filter ? Color.white : Color.white.opacity(0.15), lineWidth: selectedFilter == filter ? 2 : 1)
                                    )

                                    Text(filter.rawValue)
                                        .font(.gloucester(size: 11))
                                        .foregroundStyle(selectedFilter == filter ? .white : .white.opacity(0.5))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Action buttons — row of 3
                HStack(spacing: 10) {
                    // Save to Camera Roll
                    exportActionButton(
                        icon: savedToPhotos ? "checkmark.circle.fill" : "square.and.arrow.down",
                        label: savedToPhotos ? "Saved" : (isSaving ? "Saving..." : "Save"),
                        tint: savedToPhotos ? .green : .white
                    ) {
                        Haptics.medium()
                        Task { await saveToPhotos() }
                    }
                    .disabled(isSaving || savedToPhotos)

                    // Share (system share sheet)
                    exportActionButton(
                        icon: "square.and.arrow.up",
                        label: "Share",
                        tint: .white
                    ) {
                        Haptics.light()
                        renderedShareImage = renderExportImage()
                        if renderedShareImage != nil {
                            showShareSheet = true
                        }
                    }

                    // Instagram Story
                    exportActionButton(
                        icon: "camera.fill",
                        label: "Story",
                        tint: .white
                    ) {
                        Haptics.light()
                        guard InstagramStoriesSharer.isInstagramInstalled else {
                            showInstagramNotInstalled = true
                            return
                        }
                        shareToInstagramStory()
                    }
                }
                .padding(.horizontal, 20)

                // Advanced: Sticker Canvas
                Button {
                    Haptics.light()
                    showStickerCanvas = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.on.square.dashed")
                            .font(.system(size: 11))
                        Text("Sticker Editor")
                            .font(.gloucester(size: 13))
                    }
                    .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.05))
        .sheet(isPresented: $showShareSheet) {
            if let image = renderedShareImage {
                ShareSheet(items: [image])
            }
        }
        .alert("Instagram Not Found", isPresented: $showInstagramNotInstalled) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Install Instagram to share to your Story.")
        }
        .fullScreenCover(isPresented: $showStickerCanvas) {
            StickerCanvasView(
                durationSeconds: durationSeconds,
                subjectName: subjectName,
                subjectColor: subjectColor,
                appLeaveCount: appLeaveCount,
                caption: caption,
                subjectSegments: subjectSegments,
                subjectColorResolver: subjectColorResolver,
                videoURL: videoURL,
                thumbnailData: thumbnailData,
                sessionDate: date,
                onExport: {}
            )
        }
    }

    // MARK: - Export Canvas

    private var exportCanvas: some View {
        ZStack {
            // Background — thumbnail with color filter
            if let thumbnailData, let uiImage = UIImage(data: thumbnailData) {
                selectedFilter.apply(to:
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: canvasWidth, height: canvasHeight)
                        .clipped()
                )
            } else {
                Color(red: 0.08, green: 0.08, blue: 0.07)
            }

            // Dark translucent overlay
            if showDarkOverlay {
                Color.black.opacity(0.45)
            }

            // Poster stats
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    if showSubject {
                        Text(subjectName.uppercased())
                            .font(.gloucester(size: 13))
                            .tracking(4)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Text(formatExportDuration(durationSeconds))
                        .font(.gloucester(size: 58))
                        .foregroundStyle(.white)
                        .tracking(2)

                    if showDate {
                        Text(formatExportDate(date))
                            .font(.gloucester(size: 12))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }

                Spacer()

                if showBranding {
                    Text("Pigeon.")
                        .font(.gloucester(size: 17))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.bottom, 32)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - UI Components

    private func exportChip(_ label: String, isOn: Binding<Bool>, icon: String) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.gloucester(size: 13))
            }
            .foregroundStyle(isOn.wrappedValue ? .white : .white.opacity(0.35))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOn.wrappedValue ? .white.opacity(0.15) : .white.opacity(0.05))
            .clipShape(Capsule())
        }
    }

    private func exportActionButton(icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.gloucester(size: 12))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Render

    @MainActor
    private func renderExportImage() -> UIImage? {
        let renderer = ImageRenderer(content:
            exportCanvas
                .frame(width: canvasWidth, height: canvasHeight)
        )
        renderer.scale = 3
        return renderer.uiImage
    }

    // MARK: - Save to Photos

    @MainActor
    private func saveToPhotos() async {
        isSaving = true
        guard let image = renderExportImage() else {
            isSaving = false
            return
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            isSaving = false
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                if let data = image.jpegData(compressionQuality: 0.95) {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                }
            }
            savedToPhotos = true
            Haptics.success()
        } catch {
            print("[EXPORT] Failed to save: \(error.localizedDescription)")
        }
        isSaving = false
    }

    // MARK: - Instagram Story

    @MainActor
    private func shareToInstagramStory() {
        guard let image = renderExportImage(),
              let pngData = image.pngData() else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "instagram-stories://share?source_application=\(bundleID)") else { return }
        guard UIApplication.shared.canOpenURL(url) else {
            showInstagramNotInstalled = true
            return
        }

        let pasteboardItems: [[String: Any]] = [
            ["com.instagram.sharedSticker.backgroundImage": pngData]
        ]
        let options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(60 * 5)
        ]
        UIPasteboard.general.setItems(pasteboardItems, options: options)
        UIApplication.shared.open(url)
    }

    // MARK: - Formatting

    private func formatExportDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        } else if m > 0 {
            return "\(m)m \(s)s"
        }
        return "\(s)s"
    }

    private func formatExportDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d · h:mm a"
        return formatter.string(from: date).uppercased()
    }
}

// MARK: - ShareSheet (UIKit wrapper for UIActivityViewController)

/// Safe UIKit share sheet wrapper presented via `.sheet` to avoid
/// presentation crashes from fullScreenCover chains.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

