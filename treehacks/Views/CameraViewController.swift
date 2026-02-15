//
//  CameraViewController.swift
//  treehacks
//
//  AR-based camera view controller that detects faces using Vision,
//  recognises them via FaceRecognitionModel, and renders floating
//  name + relationship labels in the AR scene.
//

import ARKit
import Vision
import UIKit
import SceneKit
import CoreMedia
import SwiftUI

class CameraViewController: UIViewController, ARSessionDelegate {

    // MARK: - Properties

    var arView: ARSCNView!
    var faceRecognitionModel: FaceRecognitionModel!
    var labelNodes: [UUID: SCNNode] = [:]

    /// Transparent overlay for drawing 2D bounding boxes over detected faces.
    private var boundingBoxOverlay: UIView!
    /// Reusable shape layers for bounding boxes (avoids repeated allocation).
    private var boundingBoxLayers: [CAShapeLayer] = []

    /// Prevents overlapping Vision requests.
    private var isProcessingFrame = false
    /// Throttle: minimum interval between frame processing (seconds).
    private var lastProcessedTime: TimeInterval = 0
    private let processingInterval: TimeInterval = 0.5

    /// Called on every AR frame for external processing (e.g. clip indexing).
    var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?

    /// Toggle verbose face embedding logging.
    static let logDetectedFaceEmbeddings = true

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup AR View
        arView = ARSCNView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.delegate = self
        arView.session.delegate = self
        view.addSubview(arView)

        // Setup bounding box overlay (sits on top of the AR view)
        boundingBoxOverlay = UIView(frame: view.bounds)
        boundingBoxOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        boundingBoxOverlay.backgroundColor = .clear
        boundingBoxOverlay.isUserInteractionEnabled = false
        view.addSubview(boundingBoxOverlay)

        // Initialize face recognition model (reads from shared ContactStore)
        faceRecognitionModel = FaceRecognitionModel()

        // Configure AR session for world tracking
        let configuration = ARWorldTrackingConfiguration()
        arView.session.run(configuration)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Resume the AR session when switching back to this view
        let configuration = ARWorldTrackingConfiguration()
        arView.session.run(configuration)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arView.session.pause()
    }
}

// MARK: - ARSCNViewDelegate & ARSessionDelegate

extension CameraViewController: ARSCNViewDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Forward frame for external processing (clip indexing)
        let pixelBuffer = frame.capturedImage
        let timestamp = CMTime(seconds: frame.timestamp, preferredTimescale: 600)
        onFrameCaptured?(pixelBuffer, timestamp)

        // Throttle: skip frames if we're already processing or if not enough time has passed
        let currentTime = frame.timestamp
        guard !isProcessingFrame,
              currentTime - lastProcessedTime >= processingInterval else { return }

        lastProcessedTime = currentTime
        isProcessingFrame = true

        // Run face detection off the main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.processFaceDetection(frame: frame)
        }
    }
}

// MARK: - Face Detection

extension CameraViewController {

    func processFaceDetection(frame: ARFrame) {
        let pixelBuffer = frame.capturedImage

        // Create face detection request
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("[FaceDetection] Error: \(error)")
                self.isProcessingFrame = false
                return
            }

            guard let observations = request.results as? [VNFaceObservation] else {
                self.isProcessingFrame = false
                return
            }

            DispatchQueue.main.async {
                self.handleFaceDetections(observations, frame: frame)
                self.isProcessingFrame = false
            }
        }

        // ARKit captures in landscape-right orientation
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([faceDetectionRequest])
        } catch {
            print("[FaceDetection] Failed to perform detection: \(error)")
            isProcessingFrame = false
        }
    }

    func handleFaceDetections(_ faces: [VNFaceObservation], frame: ARFrame) {
        // Draw 2D bounding boxes around all detected faces
        drawBoundingBoxes(for: faces)

        print("[FaceDetection] Detected \(faces.count) face(s)")

        var newLabels: [UUID: (person: Person, position: SCNVector3)] = [:]

        for (index, face) in faces.enumerated() {
            // Extract facial features for this face and log them
            let features = faceRecognitionModel.extractFaceFeatures(face, from: frame)
            if Self.logDetectedFaceEmbeddings {
                logDetectedFaceFeatures(features, faceIndex: index, boundingBox: face.boundingBox)
            }

            // Convert face bounding box to world position
            guard let worldPosition = getWorldPosition(for: face, in: frame) else { continue }

            // Attempt recognition using pre-extracted features (avoids re-extraction)
            var person: Person? = nil
            if let features = features {
                person = faceRecognitionModel.matchPerson(for: features)
            }

            if let person = person {
                // Reuse an existing tracked face ID if close enough, otherwise assign a new one
                let faceID = findClosestExistingFace(at: worldPosition) ?? UUID()
                newLabels[faceID] = (person, worldPosition)
            }
        }

        // Update or create labels for active faces
        let activeFaceIDs = Set(newLabels.keys)
        for (faceID, info) in newLabels {
            updateARLabel(for: faceID, person: info.person, at: info.position)
        }

        // Remove labels for faces no longer detected
        removeInactiveLabels(activeFaceIDs: activeFaceIDs)
    }

    /// Log the extracted face embedding array for every detected face.
    private func logDetectedFaceFeatures(_ features: [Float]?, faceIndex: Int, boundingBox: CGRect) {
        guard let features = features else {
            print("[FaceDetection] Face #\(faceIndex + 1): could not extract features")
            return
        }
        // print("[FaceDetection] Face #\(faceIndex + 1) faceEmbedding: \(features)")
    }

    /// Match a new detection to an existing tracked face by spatial proximity.
    func findClosestExistingFace(at position: SCNVector3) -> UUID? {
        let threshold: Float = 0.3 // 30cm tolerance
        var closestID: UUID?
        var closestDistance: Float = threshold

        for (id, node) in labelNodes {
            let dx = node.position.x - position.x
            let dy = node.position.y - position.y
            let dz = node.position.z - position.z
            let distance = sqrt(dx * dx + dy * dy + dz * dz)
            if distance < closestDistance {
                closestDistance = distance
                closestID = id
            }
        }

        return closestID
    }
}

// MARK: - Face Bounding Boxes

extension CameraViewController {

    /// Draw 2D bounding boxes on the overlay for each detected face.
    func drawBoundingBoxes(for faces: [VNFaceObservation]) {
        // Remove previous bounding box layers
        for layer in boundingBoxLayers {
            layer.removeFromSuperlayer()
        }
        boundingBoxLayers.removeAll()

        let overlayBounds = boundingBoxOverlay.bounds

        for face in faces {
            // Vision bounding box: normalized (0-1), origin at bottom-left
            // Convert to UIKit coordinates: origin at top-left
            let box = face.boundingBox
            let rect = CGRect(
                x: box.origin.x * overlayBounds.width,
                y: (1.0 - box.origin.y - box.height) * overlayBounds.height,
                width: box.width * overlayBounds.width,
                height: box.height * overlayBounds.height
            )

            let shapeLayer = CAShapeLayer()
            shapeLayer.frame = rect
            shapeLayer.borderColor = UIColor.systemGray.cgColor
            shapeLayer.borderWidth = 2.5
            shapeLayer.cornerRadius = 6
            shapeLayer.backgroundColor = UIColor.clear.cgColor

            boundingBoxOverlay.layer.addSublayer(shapeLayer)
            boundingBoxLayers.append(shapeLayer)
        }
    }
}

// MARK: - World Position Estimation

extension CameraViewController {

    /// Normalized Y: aim ray at forehead (e.g. 0.88 = 88% up from bottom of face).
    private static let foreheadLevelInFace: CGFloat = 0.88

    /// World offset (meters) above the estimated forehead point.
    private static let tagHeightAboveForehead: Float = 0.20

    /// Face scale → distance: bigger face (larger bbox height) = closer.
    private static let distanceFromFaceScale: (min: Float, max: Float, scaleFactor: Float) = (0.7, 3.0, 0.28)

    func getWorldPosition(for face: VNFaceObservation, in frame: ARFrame) -> SCNVector3? {
        let viewportSize = arView.bounds.size
        let b = face.boundingBox

        // 1. Calculate forehead in normalized Vision coordinates (origin: bottom-left)
        let foreheadY = b.minY + b.height * Self.foreheadLevelInFace

        // 2. Map to screen coordinates (flip Y for UIKit's top-left origin)
        let screenPoint = CGPoint(
            x: b.midX * viewportSize.width,
            y: (1.0 - foreheadY) * viewportSize.height
        )

        // 3. Raycast into 3D space
        let cameraTransform = frame.camera.transform
        let cameraPos = SCNVector3(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        let near = arView.unprojectPoint(SCNVector3(screenPoint.x, screenPoint.y, 0))
        let far = arView.unprojectPoint(SCNVector3(screenPoint.x, screenPoint.y, 1))

        let dx = Float(far.x - near.x)
        let dy = Float(far.y - near.y)
        let dz = Float(far.z - near.z)
        let len = sqrt(dx * dx + dy * dy + dz * dz)

        guard len > 1e-6 else {
            let fx = -cameraTransform.columns.2.x
            let fy = -cameraTransform.columns.2.y
            let fz = -cameraTransform.columns.2.z
            let d = Self.distanceFromFaceScale.max
            return SCNVector3(
                cameraPos.x + fx * d,
                cameraPos.y + fy * d + Self.tagHeightAboveForehead,
                cameraPos.z + fz * d
            )
        }

        let faceHeightNorm = Float(b.height)
        let estimatedDistance = faceHeightNorm > 0.05
            ? min(Self.distanceFromFaceScale.max, max(Self.distanceFromFaceScale.min, Self.distanceFromFaceScale.scaleFactor / faceHeightNorm))
            : Self.distanceFromFaceScale.max

        let scale = estimatedDistance / len
        let foreheadWorld = SCNVector3(
            cameraPos.x + dx * scale,
            cameraPos.y + dy * scale,
            cameraPos.z + dz * scale
        )

        return SCNVector3(foreheadWorld.x, foreheadWorld.y + Self.tagHeightAboveForehead, foreheadWorld.z)
    }
}

// MARK: - AR Label Management
// Styling: createLabelNode (font, colors, scale, panel).
// Position: getWorldPosition (scale-based, above forehead).

extension CameraViewController {

    func updateARLabel(for faceID: UUID, person: Person, at position: SCNVector3) {
        if let existingNode = labelNodes[faceID] {
            // Smoothly animate position update
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.3
            existingNode.position = position
            SCNTransaction.commit()
        } else {
            // Create new label node
            let labelNode = createLabelNode(for: person)
            labelNode.position = position

            arView.scene.rootNode.addChildNode(labelNode)
            labelNodes[faceID] = labelNode
        }
    }

    /// Name + relationship tag styling. Position is set in getWorldPosition.
    func createLabelNode(for person: Person) -> SCNNode {
        let containerNode = SCNNode()
        let displayText = "\(person.name)\n\(person.relationship)"
        let text = SCNText(string: displayText, extrusionDepth: 1.0)
        text.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        text.flatness = 0.1
        text.firstMaterial?.diffuse.contents = UIColor.white

        let textNode = SCNNode(geometry: text)
        textNode.scale = SCNVector3(0.002, 0.002, 0.002)

        // Center the text horizontally and vertically (accounting for font baselines)
        let (min, max) = textNode.boundingBox
        let width = max.x - min.x
        let height = max.y - min.y

        // Add min.x and min.y to perfectly center the true geometry
        textNode.pivot = SCNMatrix4MakeTranslation(min.x + width / 2, min.y + height / 2, 0)

        // Create background panel
        let panelWidth = CGFloat(width) * 0.002 + 0.04
        let panelHeight = CGFloat(height) * 0.002 + 0.03
        let panel = SCNPlane(width: panelWidth, height: panelHeight)
        panel.cornerRadius = 0.01
        panel.firstMaterial?.diffuse.contents = UIColor.black.withAlphaComponent(0.7)

        let panelNode = SCNNode(geometry: panel)
        panelNode.position = SCNVector3(0, 0, -0.001)

        containerNode.addChildNode(panelNode)
        containerNode.addChildNode(textNode)

        // Billboard constraint to always face camera
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = [.Y]
        containerNode.constraints = [billboardConstraint]

        return containerNode
    }

    func removeInactiveLabels(activeFaceIDs: Set<UUID>) {
        let inactiveIDs = Set(labelNodes.keys).subtracting(activeFaceIDs)

        for id in inactiveIDs {
            labelNodes[id]?.removeFromParentNode()
            labelNodes.removeValue(forKey: id)
        }
    }
}

// MARK: - SwiftUI Wrapper

/// UIViewControllerRepresentable that embeds the AR-based camera view
/// with face recognition and floating name labels.
struct ARCameraContainerView: UIViewControllerRepresentable {
    var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onFrameCaptured = onFrameCaptured
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.onFrameCaptured = onFrameCaptured
    }
}
