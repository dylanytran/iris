//
//  FrameAnalyzer.swift
//  treehacks
//
//  Uses Apple Vision's VNClassifyImageRequest to analyze video frames
//  and produce descriptive keywords for scene/object content.
//

import Vision
import CoreVideo

final class FrameAnalyzer {

    /// Maximum number of top labels to return per frame.
    private let maxLabels = 8

    /// Minimum confidence threshold for a label to be included.
    private let confidenceThreshold: Float = 0.15

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
}
