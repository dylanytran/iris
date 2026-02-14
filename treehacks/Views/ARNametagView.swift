//
//  ARNametagView.swift
//  treehacks
//
//  Renders a RealityKit AR experience that detects people via body tracking
//  and shows a nametag above each detected body.
//

import SwiftUI
import RealityKit
import ARKit

// MARK: - SwiftUI wrapper

struct ARNametagView: View {
    var body: some View {
        ARNametagViewRepresentable()
            .ignoresSafeArea()
    }
}

// MARK: - UIViewRepresentable

struct ARNametagViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.session.delegate = context.coordinator
        context.coordinator.arView = arView
        context.coordinator.setupSession()
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator (ARSessionDelegate)

    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        private let displayName = "John Doe"
        private var bodyAnchorToNametag: [UUID: (AnchorEntity, Entity)] = [:]

        func setupSession() {
            guard let arView = arView else { return }
            let config = ARBodyTrackingConfiguration()
            config.isAutoFocusEnabled = true
            config.frameSemantics = .bodyDetection
            arView.session.run(config)
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let arView = arView else { return }
            for anchor in anchors {
                guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
                addNametag(for: bodyAnchor, in: arView)
            }
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            guard let arView = arView else { return }
            for anchor in anchors {
                guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
                let id = bodyAnchor.identifier
                if bodyAnchorToNametag[id] == nil {
                    addNametag(for: bodyAnchor, in: arView)
                } else {
                    updateNametagPosition(for: bodyAnchor, in: arView)
                }
            }
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
                removeNametag(for: bodyAnchor.identifier)
            }
        }

        private func addNametag(for bodyAnchor: ARBodyAnchor, in arView: ARView) {
            let anchorEntity = AnchorEntity(anchor: bodyAnchor)
            guard let nametagEntity = makeNametagEntity() else { return }

            positionNametag(nametagEntity, above: bodyAnchor)
            anchorEntity.addChild(nametagEntity)
            arView.scene.addAnchor(anchorEntity)
            bodyAnchorToNametag[bodyAnchor.identifier] = (anchorEntity, nametagEntity)
        }

        private func updateNametagPosition(for bodyAnchor: ARBodyAnchor, in arView: ARView) {
            guard let (_, nametagEntity) = bodyAnchorToNametag[bodyAnchor.identifier] else { return }
            positionNametag(nametagEntity, above: bodyAnchor)
        }

        private func removeNametag(for anchorId: UUID) {
            guard let (anchorEntity, _) = bodyAnchorToNametag[anchorId] else { return }
            anchorEntity.removeFromParent()
            bodyAnchorToNametag.removeValue(forKey: anchorId)
        }

        private func positionNametag(_ nametag: Entity, above bodyAnchor: ARBodyAnchor) {
            let headPosition = headPositionAboveBody(bodyAnchor)
            nametag.position = headPosition
        }

        private func headPositionAboveBody(_ bodyAnchor: ARBodyAnchor) -> SIMD3<Float> {
            let skeleton = bodyAnchor.skeleton
            let definition = skeleton.definition
            let headJointName = ARSkeleton.JointName(rawValue: "head_joint")
            let headIndex = definition.index(for: headJointName)

            let jointTransforms = skeleton.jointModelTransforms
            guard headIndex >= 0, headIndex < jointTransforms.count else {
                return SIMD3<Float>(0, 0.5, 0)
            }

            let headTransform = jointTransforms[headIndex]
            let headOffset = SIMD3<Float>(
                headTransform.columns.3.x,
                headTransform.columns.3.y,
                headTransform.columns.3.z
            )
            // Place nametag well above the head (Y is up in skeleton space).
            // Add ~0.25 m so it floats above the person.
            return headOffset + SIMD3<Float>(0, 0.25, 0)
        }

        private func makeNametagEntity() -> Entity? {
            let container = Entity()

            let boxWidth: Float = 0.42
            let boxHeight: Float = 0.11
            let boxDepth: Float = 0.025

            let containerFrame = CGRect(
                x: CGFloat(-boxWidth / 2),
                y: CGFloat(-boxHeight / 2),
                width: CGFloat(boxWidth),
                height: CGFloat(boxHeight)
            )
            let textMesh = MeshResource.generateText(
                displayName,
                extrusionDepth: 0.01,
                font: .systemFont(ofSize: 0.085),
                containerFrame: containerFrame,
                alignment: .center,
                lineBreakMode: .byTruncatingTail
            )

            let textMaterial = SimpleMaterial(color: .white, isMetallic: false)
            let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
            textEntity.scale = SIMD3(repeating: 1)

            let boxMesh = MeshResource.generateBox(width: boxWidth, height: boxHeight, depth: boxDepth)
            let boxMaterial = SimpleMaterial(
                color: UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1),
                isMetallic: false
            )
            let backEntity = ModelEntity(mesh: boxMesh, materials: [boxMaterial])
            backEntity.position = SIMD3<Float>(0, 0, -boxDepth / 2 - 0.004)
            container.addChild(backEntity)
            container.addChild(textEntity)

            return container
        }
    }
}

#Preview {
    ARNametagView()
}
