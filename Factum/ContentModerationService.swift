//
//  ContentModerationService.swift
//  Factum
//
//  On-device content moderation to ensure all posts are SFW.
//  Uses SensitiveContentAnalysis for nudity detection (when available)
//  and Vision ClassifyImageRequest as a fallback.
//

import Foundation
import UIKit
import Vision
import SensitiveContentAnalysis

enum ContentModerationResult {
    case safe
    case flagged(reason: String)
}

actor ContentModerationService {
    static let shared = ContentModerationService()
    
    // MARK: - Text Moderation
    
    /// Checks caption and description text for explicit/inappropriate content.
    func checkText(_ texts: [String]) -> ContentModerationResult {
        let blockedPatterns: [String] = [
            "\\bnude\\b", "\\bnudes\\b", "\\bnudity\\b",
            "\\bnsfw\\b",
            "\\bporn\\b", "\\bporno\\b", "\\bpornography\\b",
            "\\bxxx\\b",
            "\\bhentai\\b",
            "\\bsex\\b(?!ton)",  // "sex" but not "sexton"
            "\\bsexy\\b",
            "\\berotic\\b",
            "\\bexplicit\\b",
            "\\bobscene\\b",
            "\\bfuck\\b", "\\bfucking\\b", "\\bfucker\\b",
            "\\bshit\\b", "\\bshitty\\b",
            "\\bass\\b", "\\basshole\\b",
            "\\bbitch\\b",
            "\\bdick\\b(?!ens)",  // "dick" but not "dickens"
            "\\bcock\\b",
            "\\bslut\\b",
            "\\bwhore\\b",
            "\\bretard\\b", "\\bretarded\\b",
            "\\bnigger\\b", "\\bnigga\\b",
            "\\bfag\\b", "\\bfaggot\\b",
        ]
        
        let combined = texts.joined(separator: " ").lowercased()
        
        for pattern in blockedPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(combined.startIndex..., in: combined)
                if regex.firstMatch(in: combined, range: range) != nil {
                    return .flagged(reason: "Your text contains inappropriate language. Please revise before posting.")
                }
            }
        }
        
        return .safe
    }
    
    // MARK: - Image Moderation
    
    /// Checks a thumbnail image for NSFW content using on-device analysis.
    func checkImage(_ imageData: Data) async -> ContentModerationResult {
        // Try SensitiveContentAnalysis first (Apple's built-in nudity detector)
        let scaResult = await checkWithSensitiveContentAnalysis(imageData)
        if case .flagged = scaResult {
            return scaResult
        }
        
        // Fallback: use Vision ClassifyImageRequest
        let visionResult = await checkWithVisionClassification(imageData)
        if case .flagged = visionResult {
            return visionResult
        }
        
        return .safe
    }
    
    // MARK: - SensitiveContentAnalysis
    
    private func checkWithSensitiveContentAnalysis(_ imageData: Data) async -> ContentModerationResult {
        let analyzer = SCSensitivityAnalyzer()
        
        // Check if the framework is available (requires user to enable in Settings)
        guard analyzer.analysisPolicy != .disabled else {
            // Framework not available — fall through to Vision fallback
            return .safe
        }
        
        guard let cgImage = UIImage(data: imageData)?.cgImage else {
            return .safe
        }
        
        do {
            let analysis = try await analyzer.analyzeImage(cgImage)
            if analysis.isSensitive {
                return .flagged(reason: "This image appears to contain sensitive content. Please use an appropriate image for your study session post.")
            }
        } catch {
            print("SensitiveContentAnalysis error: \(error)")
            // Don't block on analysis errors — fall through to Vision
        }
        
        return .safe
    }
    
    // MARK: - Vision Classification Fallback
    
    private func checkWithVisionClassification(_ imageData: Data) async -> ContentModerationResult {
        guard let cgImage = UIImage(data: imageData)?.cgImage else {
            return .safe
        }
        
        // NSFW-adjacent identifiers that Vision's built-in classifier may return
        let flaggedIdentifiers: Set<String> = [
            "Explicit", "Racy", "Adult",
            "Lingerie", "Bikini", "Swimwear",
        ]
        
        // Confidence threshold — only flag if classifier is reasonably confident
        let confidenceThreshold: Float = 0.6
        
        do {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])
            
            if let results = request.results {
                for observation in results {
                    let id = observation.identifier
                    if flaggedIdentifiers.contains(id) && observation.confidence >= confidenceThreshold {
                        return .flagged(reason: "This image may contain inappropriate content. Please use an appropriate image for your study session post.")
                    }
                }
            }
        } catch {
            print("Vision classification error: \(error)")
        }
        
        return .safe
    }
}
