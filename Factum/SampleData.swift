//
//  SampleData.swift
//  Factum
//
//  Shared user identity for the local user
//

import Foundation

struct SampleData {
    /// A stable user ID that persists across app launches.
    static let currentUserID: UUID = {
        let key = "factum_currentUserID"
        if let stored = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let newID = UUID()
        UserDefaults.standard.set(newID.uuidString, forKey: key)
        return newID
    }()
}
