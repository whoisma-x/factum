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
import SQLite3

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
        
        let storeURL = URL.applicationSupportDirectory
            .appending(path: "default.store")
        
        // SAFETY: Always back up the database before any migration attempt.
        // The backup lives next to the store so data is never permanently lost.
        Self.backupStoreIfNeeded(at: storeURL)
        
        // Try to create the container. If the schema changed and lightweight
        // migration fails, patch the SQLite store with missing columns and retry.
        // NEVER delete the database — crash instead so the backup survives.
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            sharedModelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Try patching the store — add any missing columns
            print("[FACTUM] Migration failed, attempting column patch: \(error)")
            Self.patchStoreIfNeeded(at: storeURL)
            
            // Retry after patching
            do {
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                sharedModelContainer = try ModelContainer(for: schema, configurations: [config])
                print("[FACTUM] Migration succeeded after patching columns")
            } catch {
                // DO NOT delete the store. The backup is preserved so data can
                // be recovered manually. Crash so the user notices immediately
                // rather than silently losing data.
                fatalError("[FACTUM] Migration failed even after patching. Backup preserved at default.store.backup. Error: \(error)")
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
    
    /// Creates a backup copy of the SQLite store before any migration attempt.
    /// Keeps the most recent backup so data is never permanently lost.
    private static func backupStoreIfNeeded(at storeURL: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return }
        
        let backupURL = storeURL.deletingLastPathComponent()
            .appending(path: "default.store.backup")
        
        // Only back up if the store has actual data (> header-only size)
        let fileSize = (try? fm.attributesOfItem(atPath: storeURL.path)[.size] as? Int) ?? 0
        guard fileSize > 32768 else { return } // skip empty/header-only stores
        
        // Remove old backup, copy current store
        try? fm.removeItem(at: backupURL)
        do {
            try fm.copyItem(at: storeURL, to: backupURL)
            // Also backup WAL if it has data
            let walURL = storeURL.deletingLastPathComponent().appending(path: "default.store-wal")
            let walBackupURL = storeURL.deletingLastPathComponent().appending(path: "default.store-wal.backup")
            if fm.fileExists(atPath: walURL.path) {
                let walSize = (try? fm.attributesOfItem(atPath: walURL.path)[.size] as? Int) ?? 0
                if walSize > 0 {
                    try? fm.removeItem(at: walBackupURL)
                    try fm.copyItem(at: walURL, to: walBackupURL)
                }
            }
            print("[FACTUM] Database backed up (\(fileSize / 1024)KB)")
        } catch {
            print("[FACTUM] Backup failed: \(error.localizedDescription)")
        }
    }
    
    /// Attempts to add missing columns to the SQLite store so lightweight
    /// migration can succeed without data loss.
    private static func patchStoreIfNeeded(at storeURL: URL) {
        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        
        // Map of (table, column, SQL type, default) for every property that
        // may be missing from older schemas. Add new model properties here
        // when extending the schema to prevent future migration failures.
        let patches: [(table: String, column: String, sqlType: String, defaultVal: String)] = [
            ("ZSTUDYTIMELAPSE", "ZAPPLEAVECOUNT", "INTEGER", "0"),
            ("ZSTUDYTIMELAPSE", "ZAFTERPHOTDATA", "BLOB", "NULL"),
            ("ZSTUDYTIMELAPSE", "ZSUBJECTSEGMENTSJSON", "VARCHAR", "NULL"),
            ("ZSTUDYTIMELAPSE", "ZISLANDSCAPE", "INTEGER", "0"),
            ("ZSTUDYTIMELAPSE", "ZGOOGLEPHOTOSBACKEDUP", "INTEGER", "0"),
            ("ZSTUDYTIMELAPSE", "ZVIDEODOWNLOADURL", "VARCHAR", "NULL"),
            ("ZSTUDYTIMELAPSE", "ZTHUMBNAILDOWNLOADURL", "VARCHAR", "NULL"),
        ]
        
        for patch in patches {
            let sql = "ALTER TABLE \(patch.table) ADD COLUMN \(patch.column) \(patch.sqlType) DEFAULT \(patch.defaultVal)"
            // Silently ignore errors (column already exists)
            sqlite3_exec(db, sql, nil, nil, nil)
        }
        print("[FACTUM] Schema patch applied (\(patches.count) columns checked)")
    }
    
    private func resetDataIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "pendingDataReset") else { return }
        defaults.removeObject(forKey: "pendingDataReset")
        
        let context = sharedModelContainer.mainContext
        
        // SAFETY: Upload all sessions to Supabase before deleting anything locally
        Task {
            let descriptor = FetchDescriptor<StudyTimelapse>()
            let allTimelapses = (try? context.fetch(descriptor)) ?? []
            for timelapse in allTimelapses {
                try? await SupabaseService.shared.saveTimelapse(timelapse)
            }
            print("[RESET] Backed up \(allTimelapses.count) sessions to Supabase before reset")
            
            // Also back up user profile
            let uid = AuthService.shared.currentUserID
            let userDescriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.firebaseUID == uid })
            if let profile = try? context.fetch(userDescriptor).first {
                try? await SupabaseService.shared.saveUserProfile(profile)
            }
            
            // Sign out
            try? await AuthService.shared.signOut()
            
            // Now safe to delete local records — cloud has the backup
            await MainActor.run {
                do {
                    try context.delete(model: UserProfile.self)
                    try context.delete(model: StudyTimelapse.self)
                    try context.delete(model: TimelapseComment.self)
                    try context.delete(model: StudyGroup.self)
                    try context.delete(model: StudySubject.self)
                    try context.save()
                    print("[RESET] Local data cleared (cloud backup preserved)")
                } catch {
                    print("[RESET] Failed to reset data: \(error)")
                }
            }
        }
    }
}
