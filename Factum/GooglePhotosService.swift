//
//  GooglePhotosService.swift
//  Factum
//
//  Google Photos backup via REST API
//

import Foundation
import UIKit
import GoogleSignIn

final class GooglePhotosService {
    static let shared = GooglePhotosService()
    
    private init() {}
    
    // MARK: - Scope
    
    /// The OAuth scope needed for uploading media to Google Photos.
    static let photosScope = "https://www.googleapis.com/auth/photoslibrary.appendonly"
    
    // MARK: - UserDefaults Key
    
    private let backupEnabledKey = "googlePhotosBackupEnabled"
    
    var isBackupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: backupEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: backupEnabledKey) }
    }
    
    // MARK: - Scope Check
    
    /// Returns true if the current Google user has already granted the Photos scope.
    func hasPhotosScope() -> Bool {
        guard let grantedScopes = GIDSignIn.sharedInstance.currentUser?.grantedScopes else {
            return false
        }
        return grantedScopes.contains(Self.photosScope)
    }
    
    /// Request the photoslibrary.appendonly scope from the user.
    @MainActor
    func requestPhotosScope() async throws {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GooglePhotosError.notSignedIn
        }
        
        // Already granted
        if hasPhotosScope() { return }
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            throw GooglePhotosError.noRootViewController
        }
        
        // Walk up to the topmost presented VC
        var presentingVC = rootVC
        while let presented = presentingVC.presentedViewController {
            presentingVC = presented
        }
        
        let result = try await currentUser.addScopes([Self.photosScope], presenting: presentingVC)
        
        // Verify scope was actually granted (user could deny)
        guard let grantedScopes = result.user.grantedScopes,
              grantedScopes.contains(Self.photosScope) else {
            throw GooglePhotosError.scopeDenied
        }
    }
    
    // MARK: - Access Token
    
    /// Get a fresh Google access token with Photos scope.
    private func getAccessToken() async throws -> String {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GooglePhotosError.notSignedIn
        }
        
        // Refresh tokens if expired
        try await currentUser.refreshTokensIfNeeded()
        
        guard hasPhotosScope() else {
            throw GooglePhotosError.scopeNotGranted
        }
        
        return currentUser.accessToken.tokenString
    }
    
    // MARK: - Upload
    
    /// Upload a video file to Google Photos.
    /// Two-step process: upload bytes, then create the media item.
    func uploadVideo(localURL: URL, fileName: String, description: String) async throws {
        let token = try await getAccessToken()
        
        // Step 1: Upload raw bytes
        let uploadToken = try await uploadBytes(localURL: localURL, accessToken: token)
        
        // Step 2: Create the media item
        try await createMediaItem(
            uploadToken: uploadToken,
            fileName: fileName,
            description: description,
            accessToken: token
        )
    }
    
    /// Step 1: POST raw video bytes and get an upload token.
    private func uploadBytes(localURL: URL, accessToken: String) async throws -> String {
        let url = URL(string: "https://photoslibrary.googleapis.com/v1/uploads")!
        
        let videoData = try Data(contentsOf: localURL)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-type")
        request.setValue("video/mp4", forHTTPHeaderField: "X-Goog-Upload-Content-Type")
        request.setValue("raw", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = videoData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[PHOTOS] Upload bytes failed with status: \(statusCode)")
            throw GooglePhotosError.uploadFailed(statusCode: statusCode)
        }
        
        guard let uploadToken = String(data: data, encoding: .utf8),
              !uploadToken.isEmpty else {
            throw GooglePhotosError.invalidUploadToken
        }
        
        print("[PHOTOS] Upload bytes succeeded, got upload token")
        return uploadToken
    }
    
    /// Step 2: Create a media item using the upload token.
    private func createMediaItem(
        uploadToken: String,
        fileName: String,
        description: String,
        accessToken: String
    ) async throws {
        let url = URL(string: "https://photoslibrary.googleapis.com/v1/mediaItems:batchCreate")!
        
        let body: [String: Any] = [
            "newMediaItems": [
                [
                    "description": description,
                    "simpleMediaItem": [
                        "fileName": fileName,
                        "uploadToken": uploadToken
                    ]
                ]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            print("[PHOTOS] Create media item failed: \(statusCode) - \(responseBody)")
            throw GooglePhotosError.createMediaItemFailed(statusCode: statusCode)
        }
        
        print("[PHOTOS] Media item created successfully: \(fileName)")
    }
    
    // MARK: - Errors
    
    enum GooglePhotosError: LocalizedError {
        case notSignedIn
        case noRootViewController
        case scopeDenied
        case scopeNotGranted
        case uploadFailed(statusCode: Int)
        case invalidUploadToken
        case createMediaItemFailed(statusCode: Int)
        
        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Not signed in to Google. Please sign in first."
            case .noRootViewController:
                return "Cannot present scope request."
            case .scopeDenied:
                return "Google Photos permission was denied."
            case .scopeNotGranted:
                return "Google Photos permission not granted. Enable backup in Settings."
            case .uploadFailed(let code):
                return "Video upload to Google Photos failed (HTTP \(code))."
            case .invalidUploadToken:
                return "Google Photos returned an invalid upload token."
            case .createMediaItemFailed(let code):
                return "Could not create Google Photos media item (HTTP \(code))."
            }
        }
    }
}
