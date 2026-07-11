//
//  we_got_strava_but_for_studying_type_shiApp.swift
//  we got strava but for studying type shi
//
//  Created by Max on 7/11/26.
//

import SwiftUI
import SwiftData

@main
struct we_got_strava_but_for_studying_type_shiApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
