//
//  FactumApp.swift
//  Factum
//
//  Created by Max on 7/11/26.
//

import SwiftUI
import SwiftData
import FirebaseCore
import GoogleSignIn

@main
struct FactumApp: App {
    let sharedModelContainer: ModelContainer
    
    init() {
        // Configure Firebase FIRST, before anything touches AuthService
        FirebaseApp.configure()
        
        let schema = Schema([
            UserProfile.self,
            StudyTimelapse.self,
            TimelapseComment.self,
            StudyGroup.self,
            StudySubject.self,
        ])
        
        // Try to create the container; if the schema changed and migration
        // fails, delete the old store and retry with a fresh database.
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            sharedModelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema migration failed — wipe and retry
            let storeURL = URL.applicationSupportDirectory
                .appending(path: "default.store")
            for suffix in ["", "-shm", "-wal"] {
                let fileURL = storeURL.deletingPathExtension().appendingPathExtension("store\(suffix)")
                try? FileManager.default.removeItem(at: fileURL)
            }
            do {
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                sharedModelContainer = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AuthService.shared)
                .onAppear {
                    resetDataIfNeeded()
                    StudySubject.seedDefaultsIfNeeded(context: sharedModelContainer.mainContext)
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func resetDataIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "pendingDataReset") else { return }
        defaults.removeObject(forKey: "pendingDataReset")
        
        // Sign out of Firebase
        try? AuthService.shared.signOut()
        
        // Delete all SwiftData records
        let context = sharedModelContainer.mainContext
        do {
            try context.delete(model: UserProfile.self)
            try context.delete(model: StudyTimelapse.self)
            try context.delete(model: TimelapseComment.self)
            try context.delete(model: StudyGroup.self)
            try context.delete(model: StudySubject.self)
            try context.save()
        } catch {
            print("Failed to reset data: \(error)")
        }
    }
}
