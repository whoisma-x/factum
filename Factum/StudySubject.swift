//
//  StudySubject.swift
//  Factum
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
    
    static func color(for subjectName: String, in subjects: [StudySubject]) -> Color {
        if let match = subjects.first(where: { $0.name.caseInsensitiveCompare(subjectName) == .orderedSame }) {
            return match.color
        }
        return Color(white: 0.4)
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
