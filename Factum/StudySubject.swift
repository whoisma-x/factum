//
//  StudySubject.swift
//  Pigeon
//
//  Subject model with color coding for study sessions
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Study Subject Model

@Model
final class StudySubject {
    var id: UUID
    var name: String
    var colorHex: String
    var isUserCreated: Bool
    var sortOrder: Int
    var createdAt: Date
    
    init(name: String, colorHex: String, isUserCreated: Bool = false, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.isUserCreated = isUserCreated
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
    
    var color: Color {
        Color(hex: colorHex) ?? .gray
    }
    
    // MARK: - Default Presets
    
    static let defaultSubjects: [(String, String)] = [
        ("Math", "#3478F6"),
        ("English", "#FF3B30"),
        ("Science", "#34C759"),
        ("History", "#A2845E"),
        ("Computer Science", "#AF52DE"),
        ("Literature", "#FF9500"),
        ("Physics", "#5AC8FA"),
        ("Chemistry", "#A8CC3C"),
        ("Economics", "#FF2D55"),
        ("Psychology", "#BF5AF2"),
        ("Biology", "#00C7BE"),
        ("Spanish", "#FFCC00"),
        ("Art", "#64D2FF"),
        ("Geography", "#8E8E93"),
    ]
    
    // MARK: - Seeding
    
    static func seedDefaultsIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<StudySubject>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }
        
        for (index, (name, hex)) in defaultSubjects.enumerated() {
            let subject = StudySubject(name: name, colorHex: hex, isUserCreated: false, sortOrder: index)
            context.insert(subject)
        }
    }
    
    // MARK: - Color Lookup

    /// Builds a case-insensitive lookup dictionary from an array of subjects.
    /// Use this when performing multiple lookups against the same subject list.
    static func colorMap(from subjects: [StudySubject]) -> [String: Color] {
        Dictionary(subjects.map { ($0.name.lowercased(), $0.color) }, uniquingKeysWith: { first, _ in first })
    }

    /// A subject's colour. Matches names with surrounding spaces ignored, then
    /// uses a colour stored on the session itself. Gray is only the last resort.
    static func color(for subjectName: String, in subjects: [StudySubject], hexes: [String: String] = [:]) -> Color {
        let trimmed = subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = subjects.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return match.color
        }
        if let hex = hexes[trimmed.lowercased()], let stored = Color(hex: hex) {
            return stored
        }
        return Color(white: 0.4)
    }

    /// Colours written onto session segments, keyed by trimmed lowercase name.
    static func hexes(in segments: [SubjectSegment]) -> [String: String] {
        var map: [String: String] = [:]
        for segment in segments {
            guard let hex = segment.colorHex, Color(hex: hex) != nil else { continue }
            let key = segment.subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if map[key] == nil { map[key] = hex }
        }
        return map
    }

    static func hexes(in timelapses: [StudyTimelapse]) -> [String: String] {
        hexes(in: timelapses.flatMap(\.subjectSegments))
    }

    /// O(1) color lookup using a pre-built color map.
    static func color(for subjectName: String, using colorMap: [String: Color]) -> Color {
        colorMap[subjectName.lowercased()] ?? Color(white: 0.4)
    }
}

// MARK: - Color Hex Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
    
    var hexString: String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
