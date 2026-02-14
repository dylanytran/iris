//
//  FaceRecognitionModel.swift
//  treehacks
//

import Vision
import ARKit

class FaceRecognitionModel {
    /// Always read from the shared contact store so new/edited contacts are
    /// immediately available for recognition without requiring a reload.
    private var knownPeople: [Person] {
        ContactStore.shared.contacts
    }

    init() {
        print("[FaceRecognition] Using shared ContactStore (\(knownPeople.count) people)")
    }
    
    func recognizeFace(_ faceObservation: VNFaceObservation, from frame: ARFrame) -> Person? {
        guard let faceFeatures = extractFaceFeatures(faceObservation, from: frame) else {
            return nil
        }
        return matchPerson(for: faceFeatures)
    }
    
    /// Recognize a face from pre-extracted features (avoids re-extracting).
    /// Compares the live embedding against every stored embedding for each person
    /// and picks the highest similarity (best-of-N across all reference photos).
    func matchPerson(for faceFeatures: [Float]) -> Person? {
        var bestMatch: Person?
        var bestSimilarity: Float = 0.0
        let threshold: Float = 0.75
        
        for person in knownPeople {
            guard !person.faceEmbeddings.isEmpty else { continue }
            
            // Find the best similarity across all embeddings for this person
            var personBestSimilarity: Float = 0.0
            for embedding in person.faceEmbeddings {
                guard !embedding.isEmpty else { continue }
                if faceFeatures.count != embedding.count {
                    print("[FaceRecognition] Dimension mismatch for \(person.name): live=\(faceFeatures.count) vs stored=\(embedding.count)")
                    continue
                }
                let similarity = cosineSimilarity(faceFeatures, embedding)
                if similarity > personBestSimilarity {
                    personBestSimilarity = similarity
                }
            }
            
            print("[FaceRecognition] \(person.name): best similarity=\(personBestSimilarity) (across \(person.faceEmbeddings.count) embedding(s))")
            if personBestSimilarity > bestSimilarity && personBestSimilarity > threshold {
                bestSimilarity = personBestSimilarity
                bestMatch = person
            }
        }
        
        if let match = bestMatch {
            print("[FaceRecognition] Best match: \(match.name) (\(bestSimilarity))")
        }
        return bestMatch
    }
    
    /// Extract facial landmark features for a specific face observation.
    /// Accessible from CameraViewController for per-detection logging.
    func extractFaceFeatures(_ face: VNFaceObservation, from frame: ARFrame) -> [Float]? {
        // Constrain landmark detection to the specific detected face
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.inputFaceObservations = [face]
        
        let pixelBuffer = frame.capturedImage
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        
        do {
            try handler.perform([landmarksRequest])
            
            guard let observations = landmarksRequest.results,
                  let matchedFace = observations.first,
                  let landmarks = matchedFace.landmarks else {
                return nil
            }
            
            // Extract facial landmark features into a feature vector
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
            
            // Add geometric ratios for better recognition
            features.append(contentsOf: calculateGeometricFeatures(landmarks))
            
            return features
            
        } catch {
            print("[FaceRecognition] Failed to detect landmarks: \(error)")
            return nil
        }
    }
    
    // MARK: - Helper Methods
    
    private func normalizePoints(_ points: [CGPoint]) -> [Float] {
        return points.flatMap { [Float($0.x), Float($0.y)] }
    }
    
    private func calculateGeometricFeatures(_ landmarks: VNFaceLandmarks2D) -> [Float] {
        var geometricFeatures: [Float] = []
        
        // Eye width ratio
        if let leftEye = landmarks.leftEye,
           let rightEye = landmarks.rightEye {
            let leftEyeWidth = calculateWidth(leftEye.normalizedPoints)
            let rightEyeWidth = calculateWidth(rightEye.normalizedPoints)
            if rightEyeWidth > 0 {
                geometricFeatures.append(Float(leftEyeWidth / rightEyeWidth))
            }
        }
        
        // Eye separation (inter-pupillary distance)
        if let leftPupil = landmarks.leftPupil?.normalizedPoints.first,
           let rightPupil = landmarks.rightPupil?.normalizedPoints.first {
            let distance = sqrt(pow(rightPupil.x - leftPupil.x, 2) + pow(rightPupil.y - leftPupil.y, 2))
            geometricFeatures.append(Float(distance))
        }
        
        // Nose to mouth distance ratio
        if let nose = landmarks.nose,
           let outerLips = landmarks.outerLips {
            let noseCenterY = nose.normalizedPoints.map { $0.y }.reduce(0, +) / CGFloat(nose.normalizedPoints.count)
            let mouthCenterY = outerLips.normalizedPoints.map { $0.y }.reduce(0, +) / CGFloat(outerLips.normalizedPoints.count)
            geometricFeatures.append(Float(abs(mouthCenterY - noseCenterY)))
        }
        
        // Face aspect ratio
        if let faceContour = landmarks.faceContour {
            let width = calculateWidth(faceContour.normalizedPoints)
            let height = calculateHeight(faceContour.normalizedPoints)
            if height > 0 {
                geometricFeatures.append(Float(width / height))
            }
        }
        
        // Mouth width
        if let outerLips = landmarks.outerLips {
            let mouthWidth = calculateWidth(outerLips.normalizedPoints)
            geometricFeatures.append(Float(mouthWidth))
        }
        
        return geometricFeatures
    }
    
    private func calculateWidth(_ points: [CGPoint]) -> CGFloat {
        let xValues = points.map { $0.x }
        guard let minX = xValues.min(), let maxX = xValues.max() else { return 0 }
        return maxX - minX
    }
    
    private func calculateHeight(_ points: [CGPoint]) -> CGFloat {
        let yValues = points.map { $0.y }
        guard let minY = yValues.min(), let maxY = yValues.max() else { return 0 }
        return maxY - minY
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0, magnitudeB > 0 else { return 0.0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
}
