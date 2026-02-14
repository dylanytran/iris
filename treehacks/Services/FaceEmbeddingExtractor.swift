//
//  FaceEmbeddingExtractor.swift
//  treehacks
//
//  Extracts a face embedding from a static UIImage using the same landmark
//  pipeline as FaceRecognitionModel so that enrolled embeddings are directly
//  comparable to live-detected ones.
//

import Vision
import UIKit

enum FaceEmbeddingExtractor {

    /// Synchronously extract a face embedding from a UIImage.
    /// Returns `nil` if no face or landmarks are detected.
    ///
    /// The image's `imageOrientation` is forwarded to Vision so that
    /// landmarks are extracted in the correct coordinate space — matching
    /// the live-camera pipeline.
    nonisolated static func extractEmbedding(from image: UIImage) -> [Float]? {
        guard let cgImage = image.cgImage else { return nil }

        // Map UIImage orientation → CGImagePropertyOrientation so Vision
        // processes the pixels in the same upright orientation the user sees.
        let visionOrientation = cgImageOrientation(from: image.imageOrientation)

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: visionOrientation,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            print("[FaceEmbeddingExtractor] Vision request failed: \(error)")
            return nil
        }

        guard let observations = request.results,
              let face = observations.first,
              let landmarks = face.landmarks else {
            print("[FaceEmbeddingExtractor] No face or landmarks detected")
            return nil
        }

        // --- Build the feature vector (must mirror FaceRecognitionModel) ---

        var features: [Float] = []

        if let faceContour = landmarks.faceContour {
            features.append(contentsOf: normalizePoints(faceContour.normalizedPoints))
        }
        if let leftEye = landmarks.leftEye {
            features.append(contentsOf: normalizePoints(leftEye.normalizedPoints))
        }
        if let rightEye = landmarks.rightEye {
            features.append(contentsOf: normalizePoints(rightEye.normalizedPoints))
        }
        if let leftEyebrow = landmarks.leftEyebrow {
            features.append(contentsOf: normalizePoints(leftEyebrow.normalizedPoints))
        }
        if let rightEyebrow = landmarks.rightEyebrow {
            features.append(contentsOf: normalizePoints(rightEyebrow.normalizedPoints))
        }
        if let nose = landmarks.nose {
            features.append(contentsOf: normalizePoints(nose.normalizedPoints))
        }
        if let noseCrest = landmarks.noseCrest {
            features.append(contentsOf: normalizePoints(noseCrest.normalizedPoints))
        }
        if let medianLine = landmarks.medianLine {
            features.append(contentsOf: normalizePoints(medianLine.normalizedPoints))
        }
        if let outerLips = landmarks.outerLips {
            features.append(contentsOf: normalizePoints(outerLips.normalizedPoints))
        }
        if let innerLips = landmarks.innerLips {
            features.append(contentsOf: normalizePoints(innerLips.normalizedPoints))
        }
        if let leftPupil = landmarks.leftPupil {
            features.append(contentsOf: normalizePoints(leftPupil.normalizedPoints))
        }
        if let rightPupil = landmarks.rightPupil {
            features.append(contentsOf: normalizePoints(rightPupil.normalizedPoints))
        }

        features.append(contentsOf: calculateGeometricFeatures(landmarks))

        print("[FaceEmbeddingExtractor] Extracted \(features.count)-dim embedding")
        return features.isEmpty ? nil : features
    }

    // MARK: - Orientation mapping

    /// Maps UIImage.Orientation → CGImagePropertyOrientation.
    /// The two enums have different raw values so a manual mapping is required.
    private static func cgImageOrientation(
        from uiOrientation: UIImage.Orientation
    ) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }

    // MARK: - Helpers (identical to FaceRecognitionModel)

    private static func normalizePoints(_ points: [CGPoint]) -> [Float] {
        points.flatMap { [Float($0.x), Float($0.y)] }
    }

    private static func calculateGeometricFeatures(_ landmarks: VNFaceLandmarks2D) -> [Float] {
        var geo: [Float] = []

        if let leftEye = landmarks.leftEye,
           let rightEye = landmarks.rightEye {
            let lw = calculateWidth(leftEye.normalizedPoints)
            let rw = calculateWidth(rightEye.normalizedPoints)
            if rw > 0 { geo.append(Float(lw / rw)) }
        }

        if let lp = landmarks.leftPupil?.normalizedPoints.first,
           let rp = landmarks.rightPupil?.normalizedPoints.first {
            let d = sqrt(pow(rp.x - lp.x, 2) + pow(rp.y - lp.y, 2))
            geo.append(Float(d))
        }

        if let nose = landmarks.nose,
           let outerLips = landmarks.outerLips {
            let noseCY = nose.normalizedPoints.map(\.y).reduce(0, +) / CGFloat(nose.normalizedPoints.count)
            let mouthCY = outerLips.normalizedPoints.map(\.y).reduce(0, +) / CGFloat(outerLips.normalizedPoints.count)
            geo.append(Float(abs(mouthCY - noseCY)))
        }

        if let fc = landmarks.faceContour {
            let w = calculateWidth(fc.normalizedPoints)
            let h = calculateHeight(fc.normalizedPoints)
            if h > 0 { geo.append(Float(w / h)) }
        }

        if let ol = landmarks.outerLips {
            geo.append(Float(calculateWidth(ol.normalizedPoints)))
        }

        return geo
    }

    private static func calculateWidth(_ points: [CGPoint]) -> CGFloat {
        let xs = points.map(\.x)
        guard let lo = xs.min(), let hi = xs.max() else { return 0 }
        return hi - lo
    }

    private static func calculateHeight(_ points: [CGPoint]) -> CGFloat {
        let ys = points.map(\.y)
        guard let lo = ys.min(), let hi = ys.max() else { return 0 }
        return hi - lo
    }
}
