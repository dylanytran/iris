//
//  FrameAnalyzer.swift
//  treehacks
//
//  Uses Apple Vision's VNClassifyImageRequest to analyze video frames
//  and produce descriptive keywords for scene/object content.
//  Also provides a helper to convert frames to JPEG for the OpenAI vision API.
//

import Vision
import CoreVideo
import UIKit

final class FrameAnalyzer {

    /// Maximum number of top labels to return per frame.
    private let maxLabels = 8

    /// Minimum confidence threshold for a label to be included.
    private let confidenceThreshold: Float = 0.15

    /// Maximum dimension (width or height) for JPEG images sent to the API.
    /// Smaller = fewer tokens = cheaper. 512px is plenty for keyword extraction.
    private let maxJPEGDimension: CGFloat = 512

    /// Classify a video frame and return descriptive keywords.
    /// Runs synchronously on the caller's queue — call from a background queue.
    func classifyFrame(_ pixelBuffer: CVPixelBuffer) -> [String] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        // Filter by confidence and take top N
        let labels = observations
            .filter { $0.confidence >= confidenceThreshold }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxLabels)
            .map { formatLabel($0.identifier) }

        return labels
    }

    /// Detect any visible text in the frame (bonus context for search).
    func recognizeText(in pixelBuffer: CVPixelBuffer) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        return observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }
    }

    /// Convert Vision taxonomy identifiers (e.g., "animal_cat") to readable labels.
    private func formatLabel(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    // MARK: - JPEG Conversion (for OpenAI Vision API)

    /// Convert a CVPixelBuffer to compressed JPEG Data, resized to keep cost low.
    /// Returns nil if conversion fails.
    func pixelBufferToJPEG(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        // Render to CGImage
        let extent = ciImage.extent
        guard let cgImage = context.createCGImage(ciImage, from: extent) else {
            print("[FrameAnalyzer] Failed to create CGImage from pixel buffer")
            return nil
        }

        // Create UIImage (apply portrait rotation)
        var uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

        // Resize to keep API cost low
        let size = uiImage.size
        let longestSide = max(size.width, size.height)
        if longestSide > maxJPEGDimension {
            let scale = maxJPEGDimension / longestSide
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            uiImage = renderer.image { _ in
                uiImage.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }

        // Compress to JPEG (quality 0.5 is fine for keyword extraction)
        return uiImage.jpegData(compressionQuality: 0.5)
    }
}
