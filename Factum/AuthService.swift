//
//  AuthService.swift
//  Pigeon
//
//  Supabase Authentication + Google Sign-In
//

import Foundation
import Supabase
import GoogleSignIn
import UIKit
import AuthenticationServices
import CryptoKit

@MainActor @Observable
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
                self?.currentUser = session?.user
                self?.isSignedIn = session?.user != nil
                self?.isLoading = false
            }
        }
    }
    
    // MARK: - Sign in with Apple

    @MainActor
    func signInWithApple() async throws {
        // Prepare a secure nonce to include in the request and later pass to Supabase
        let rawNonce = Self.randomNonceString()
        let hashedNonce = Self.sha256(rawNonce)

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let coordinator = AppleSignInCoordinator()
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator

        try await coordinator.perform(controller: controller)

        guard let credential = coordinator.credential,
              let idTokenData = credential.identityToken,
              let idToken = String(data: idTokenData, encoding: .utf8) else {
            throw AuthError.missingIDToken
        }

        // Sign in to Supabase with the Apple identity token and original (unhashed) nonce
        try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: rawNonce
            )
        )

        // Update display name if provided by Apple on first sign-in
        if let fullName = credential.fullName,
           let given = fullName.givenName,
           let family = fullName.familyName {
            let name = "\(given) \(family)"
            // Best-effort: store into user metadata so it syncs across devices
            try? await supabase.auth.update(user: .init(data: ["full_name": .string(name)]))
        }
    }

    // MARK: - Apple Sign-In helpers

    private class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        var credential: ASAuthorizationAppleIDCredential?
        private var continuation: CheckedContinuation<Void, Error>?

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            // Try to find a valid window to present from
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first {
                return window
            }
            return ASPresentationAnchor()
        }

        func perform(controller: ASAuthorizationController) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                controller.performRequests()
            }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                self.credential = appleIDCredential
                continuation?.resume()
            } else {
                continuation?.resume(throwing: NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid credential"]))
            }
            continuation = nil
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
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
        currentUser = nil
        isSignedIn = false
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

