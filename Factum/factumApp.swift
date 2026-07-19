//
//  FactumApp.swift
//  Factum
//
//  Created by Max on 7/11/26.
//

import SwiftUI
import SwiftData
import GoogleSignIn
import Supabase

@main
struct FactumApp: App {
    let sharedModelContainer: ModelContainer
    @State private var deepLinkTimelapseID: String?
    
    init() {
        // Detect fresh install: UserDefaults is wiped on delete, but Keychain
        // may retain tokens. If our flag is missing, this is a new install —
        // clear any stale session so the user sees onboarding again.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasLaunchedBefore") {
            // Fresh install — clear any stale Keychain session so the user
            // sees onboarding. This runs synchronously before any UI appears.
            defaults.set(true, forKey: "hasLaunchedBefore")
            Task {
                try? await supabase.auth.signOut()
                GIDSignIn.sharedInstance.signOut()
            }
        }
        
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
            ContentView(deepLinkTimelapseID: $deepLinkTimelapseID)
                .environment(AuthService.shared)
                .onTapGesture {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
                .onAppear {
                    resetDataIfNeeded()
                }
                .onOpenURL { url in
                    // Handle factum:// deep links
                    if url.scheme == "factum", url.host == "post",
                       let id = url.pathComponents.dropFirst().first {
                        deepLinkTimelapseID = id
                        return
                    }
                    // Fall through to Google Sign-In
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func resetDataIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "pendingDataReset") else { return }
        defaults.removeObject(forKey: "pendingDataReset")
        
        // Sign out
        Task {
            try? await AuthService.shared.signOut()
        }
        
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
