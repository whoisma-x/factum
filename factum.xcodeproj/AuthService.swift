//
//  AuthService.swift
//  Factum
//
//  Firebase Authentication + Google Sign-In
//

import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

@Observable
final class AuthService {
    static let shared = AuthService()
    
    var currentUser: FirebaseAuth.User?
    var isSignedIn: Bool { currentUser != nil }
    var errorMessage: String?
    
    /// True until the first Firebase auth state callback fires.
    /// Views should wait for this to become false before checking isSignedIn.
    var isLoading: Bool = true
    
    /// Firebase UID for the signed-in user, or empty string if not signed in.
    var currentUserID: String { currentUser?.uid ?? "" }
    
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    
    private init() {
        // The listener fires once immediately with the current auth state,
        // then again whenever auth state changes.
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.currentUser = user
            self?.isLoading = false
        }
    }
    
    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    // MARK: - Google Sign-In
    
    @MainActor
    func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingClientID
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            throw AuthError.noRootViewController
        }
        
        // Walk up the presented view controller chain to find the topmost one.
        // When onboarding is shown as a fullScreenCover, rootVC isn't the
        // visible controller — Google Sign-In needs the one actually on screen.
        var presentingVC = rootVC
        while let presented = presentingVC.presentedViewController {
            presentingVC = presented
        }
        
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
        
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingIDToken
        }
        
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        
        let authResult = try await Auth.auth().signIn(with: credential)
        self.currentUser = authResult.user
    }
    
    // MARK: - Anonymous Sign-In
    
    func signInAnonymously() async throws {
        let result = try await Auth.auth().signInAnonymously()
        self.currentUser = result.user
    }
    
    // MARK: - Sign Out
    
    func signOut() throws {
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        self.currentUser = nil
    }
    
    // MARK: - Errors
    
    enum AuthError: LocalizedError {
        case missingClientID
        case noRootViewController
        case missingIDToken
        
        var errorDescription: String? {
            switch self {
            case .missingClientID:
                return "Firebase client ID not found. Check GoogleService-Info.plist."
            case .noRootViewController:
                return "Cannot find root view controller for sign-in."
            case .missingIDToken:
                return "Google Sign-In did not return an ID token."
            }
        }
    }
}
