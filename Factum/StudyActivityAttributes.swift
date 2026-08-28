//
//  StudyActivityAttributes.swift
//  Pigeon
//
//  ActivityKit attributes for the study session Live Activity / Dynamic Island.
//

import ActivityKit
import Foundation

struct StudySessionAttributes: ActivityAttributes {
    /// Static data that doesn't change during the activity.
    let subject: String
    let startDate: Date

    /// Dynamic data updated while the activity is running.
    struct ContentState: Codable, Hashable {
        let elapsedSeconds: Int
        let isPaused: Bool
    }
}
