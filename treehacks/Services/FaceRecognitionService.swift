//
//  FaceRecognitionService.swift
//  treehacks
//
//  Created by Dylan Tran on 2/14/26.
//

import Vision
import UIKit
import Combine

/// Represents a detected face with its bounding box and optional identity match.
struct DetectedFace: Identifiable {
    let id = UUID()
    let boundingBox: CGRect  // Normalized coordinates (0-1), origin bottom-left
    let landmarks: VNFaceLandmarks2D?
    var matchedPerson: Person?
    var confidence: Float = 0.0
}

/// Handles face detection using Vision framework and matches detected faces
/// against registered Person profiles using facial landmark geometry comparison.
class FaceRecognitionService: ObservableObject {

    // MARK: - Published State

    @Published var detectedFaces: [DetectedFace] = []
    @Published var isProcessing = false

    // MARK: - Configuration

    /// Minimum confidence to consider a face match valid (0-1, lower = more lenient).
    var matchThreshold: Float = 0.35

    /// Process every Nth frame to reduce CPU load
    var frameSkip: Int = 5

    // MARK: - Private

    private var frameCount = 0
    private var registeredPeople: [Person] = []
    private let processingQueue = DispatchQueue(label: "com.treehacks.faceRecognition", qos: .userInitiated)

    // MARK: - Registration

    /// Update the list of registered people for matching.
    func updateRegisteredPeople(_ people: [Person]) {
        self.registeredPeople = people
    }

    // MARK: - Frame Processing

    /// Process a video frame for face detection and recognition.
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        frameCount += 1
        guard frameCount % frameSkip == 0 else { return }

        processingQueue.async { [weak self] in
            self?.detectAndMatchFaces(in: pixelBuffer)
        }
    }

    private func detectAndMatchFaces(in pixelBuffer: CVPixelBuffer) {
        let faceDetectionRequest = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])

        do {
            try handler.perform([faceDetectionRequest])
        } catch {
            print("Face detection failed: \(error)")
            return
        }

        guard let observations = faceDetectionRequest.results else {
            DispatchQueue.main.async { self.detectedFaces = [] }
            return
        }

        var faces: [DetectedFace] = []

        for observation in observations {
            var face = DetectedFace(
                boundingBox: observation.boundingBox,
                landmarks: observation.landmarks
            )

            // Try to match against registered people
            if let landmarks = observation.landmarks,
               let descriptor = extractDescriptor(from: landmarks) {
                let match = findBestMatch(for: descriptor)
                face.matchedPerson = match?.person
                face.confidence = match?.confidence ?? 0
            }

            faces.append(face)
        }

        DispatchQueue.main.async {
            self.detectedFaces = faces
        }
    }

    // MARK: - Feature Extraction

    /// Extract a geometric descriptor vector from face landmarks.
    /// Uses ratios between landmark distances that are invariant to scale.
    static func extractDescriptor(from landmarks: VNFaceLandmarks2D) -> [Float]? {
        guard let leftEye = landmarks.leftEye?.normalizedPoints, !leftEye.isEmpty,
              let rightEye = landmarks.rightEye?.normalizedPoints, !rightEye.isEmpty,
              let nose = landmarks.nose?.normalizedPoints, !nose.isEmpty,
              let outerLips = landmarks.outerLips?.normalizedPoints, !outerLips.isEmpty,
              let faceContour = landmarks.faceContour?.normalizedPoints, !faceContour.isEmpty,
              let leftEyebrow = landmarks.leftEyebrow?.normalizedPoints, !leftEyebrow.isEmpty,
              let rightEyebrow = landmarks.rightEyebrow?.normalizedPoints, !rightEyebrow.isEmpty
        else { return nil }

        // Compute centers
        let leftEyeCenter = center(of: leftEye)
        let rightEyeCenter = center(of: rightEye)
        let noseCenter = center(of: nose)
        let mouthCenter = center(of: outerLips)
        let leftEyebrowCenter = center(of: leftEyebrow)
        let rightEyebrowCenter = center(of: rightEyebrow)

        // Reference distance: inter-eye distance (for normalization)
        let interEyeDist = distance(leftEyeCenter, rightEyeCenter)
        guard interEyeDist > 0.01 else { return nil } // Too close or invalid

        // Compute normalized features
        var features: [Float] = []

        // 1. Left eye width / inter-eye distance
        features.append(Float(width(of: leftEye) / interEyeDist))

        // 2. Right eye width / inter-eye distance
        features.append(Float(width(of: rightEye) / interEyeDist))

        // 3. Left eye height / inter-eye distance
        features.append(Float(height(of: leftEye) / interEyeDist))

        // 4. Right eye height / inter-eye distance
        features.append(Float(height(of: rightEye) / interEyeDist))

        // 5. Nose width / inter-eye distance
        features.append(Float(width(of: nose) / interEyeDist))

        // 6. Nose height / inter-eye distance
        features.append(Float(height(of: nose) / interEyeDist))

        // 7. Mouth width / inter-eye distance
        features.append(Float(width(of: outerLips) / interEyeDist))

        // 8. Mouth height / inter-eye distance
        features.append(Float(height(of: outerLips) / interEyeDist))

        // 9. Distance from nose to mouth / inter-eye distance
        features.append(Float(distance(noseCenter, mouthCenter) / interEyeDist))

        // 10. Distance from left eye to nose / inter-eye distance
        features.append(Float(distance(leftEyeCenter, noseCenter) / interEyeDist))

        // 11. Distance from right eye to nose / inter-eye distance
        features.append(Float(distance(rightEyeCenter, noseCenter) / interEyeDist))

        // 12. Left eyebrow to left eye distance / inter-eye distance
        features.append(Float(distance(leftEyebrowCenter, leftEyeCenter) / interEyeDist))

        // 13. Right eyebrow to right eye distance / inter-eye distance
        features.append(Float(distance(rightEyebrowCenter, rightEyeCenter) / interEyeDist))

        // 14. Face contour width / inter-eye distance
        if faceContour.count >= 2 {
            let faceWidth = distance(faceContour.first!, faceContour.last!)
            features.append(Float(faceWidth / interEyeDist))
        } else {
            features.append(0)
        }

        // 15. Vertical symmetry: |left eye y - right eye y| / inter-eye distance
        features.append(Float(abs(leftEyeCenter.y - rightEyeCenter.y) / interEyeDist))

        return features
    }

    func extractDescriptor(from landmarks: VNFaceLandmarks2D) -> [Float]? {
        Self.extractDescriptor(from: landmarks)
    }

    // MARK: - Matching

    private func findBestMatch(for descriptor: [Float]) -> (person: Person, confidence: Float)? {
        var bestMatch: Person?
        var bestDistance: Float = Float.greatestFiniteMagnitude

        for person in registeredPeople {
            guard let storedDescriptor = person.faceDescriptor,
                  storedDescriptor.count == descriptor.count else { continue }

            let dist = euclideanDistance(descriptor, storedDescriptor)
            if dist < bestDistance {
                bestDistance = dist
                bestMatch = person
            }
        }

        guard let match = bestMatch, bestDistance < matchThreshold else { return nil }

        // Convert distance to confidence (0-1, higher is better)
        let confidence = max(0, 1.0 - (bestDistance / matchThreshold))
        return (match, confidence)
    }

    // MARK: - Math Helpers

    private static func center(of points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }

    private static func width(of points: [CGPoint]) -> CGFloat {
        let xs = points.map(\.x)
        return (xs.max() ?? 0) - (xs.min() ?? 0)
    }

    private static func height(of points: [CGPoint]) -> CGFloat {
        let ys = points.map(\.y)
        return (ys.max() ?? 0) - (ys.min() ?? 0)
    }

    private func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        sqrt(zip(a, b).reduce(0) { $0 + pow($1.0 - $1.1, 2) })
    }
}
