//
//  AuthService.swift
//  Factum
//
//  Supabase Authentication + Google Sign-In
//

import Foundation
import Supabase
import GoogleSignIn
import UIKit

@Observable
final class AuthService {
    static let shared = AuthService()
    
    var currentUser: User?
    var isSignedIn: Bool = false
    var errorMessage: String?
    
    /// True until the first Supabase auth state callback fires.
    /// Views should wait for this to become false before checking isSignedIn.
    var isLoading: Bool = true
    
    /// Supabase Auth UID for the signed-in user, or empty string if not signed in.
    var currentUserID: String { currentUser?.id.uuidString ?? "" }
    
    private init() {
        // Configure Google Sign-In with the OAuth client ID.
        // Previously this was done by FirebaseApp.configure() reading
        // GoogleService-Info.plist, but since we migrated to Supabase we
        // need to set it manually.
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "986757686148-p6dgau81ac6u8lfr03mku2k8746bjji5.apps.googleusercontent.com"
        )
        
        // Check for existing session immediately
        currentUser = supabase.auth.currentUser
        isSignedIn = currentUser != nil
        
        // Listen for auth state changes
        Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                guard [.initialSession, .signedIn, .signedOut].contains(event) else { continue }
                await MainActor.run {
                    self?.currentUser = session?.user
                    self?.isSignedIn = session?.user != nil
                    self?.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Google Sign-In
    
    @MainActor
    func signInWithGoogle() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            throw AuthError.noRootViewController
        }
        
        // Walk up the presented view controller chain to find the topmost one.
        var presentingVC = rootVC
        while let presented = presentingVC.presentedViewController {
            presentingVC = presented
        }
        
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
        
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingIDToken
        }
        
        let accessToken = result.user.accessToken.tokenString
        
        try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken
            )
        )
    }
    
    // MARK: - Email Sign-In
    
    func signInWithEmail(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }
    
    // MARK: - Email Sign-Up
    
    func signUpWithEmail(email: String, password: String, displayName: String) async throws {
        try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["full_name": .string(displayName)]
        )
    }
    
    // MARK: - Anonymous Sign-In
    
    func signInAnonymously() async throws {
        try await supabase.auth.signInAnonymously()
    }
    
    // MARK: - Sign Out
    
    func signOut() async throws {
        try await supabase.auth.signOut()
        GIDSignIn.sharedInstance.signOut()
        GooglePhotosService.shared.isBackupEnabled = false
        await MainActor.run {
            self.currentUser = nil
            self.isSignedIn = false
        }
    }
    
    // MARK: - Errors
    
    enum AuthError: LocalizedError {
        case noRootViewController
        case missingIDToken
        
        var errorDescription: String? {
            switch self {
            case .noRootViewController:
                return "Cannot find root view controller for sign-in."
            case .missingIDToken:
                return "Google Sign-In did not return an ID token."
            }
        }
    }
}
