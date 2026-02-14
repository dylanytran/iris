//
//  FaceOverlayView.swift
//  treehacks
//
//  Created by Dylan Tran on 2/14/26.
//

import SwiftUI

/// Draws face bounding boxes and name labels over the camera preview.
/// Converts Vision's normalized coordinates to screen coordinates.
struct FaceOverlayView: View {

    let faces: [DetectedFace]
    let viewSize: CGSize

    var body: some View {
        ZStack {
            ForEach(faces) { face in
                let rect = convertBoundingBox(face.boundingBox, in: viewSize)

                // Bounding box
                RoundedRectangle(cornerRadius: 8)
                    .stroke(face.matchedPerson != nil ? Color.green : Color.white, lineWidth: 3)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                // Name label above the bounding box
                if let person = face.matchedPerson {
                    VStack(spacing: 4) {
                        Text(person.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)

                        if !person.relationship.isEmpty {
                            Text(person.relationship)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.85))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    )
                    .position(x: rect.midX, y: rect.minY - 40)
                }
            }
        }
    }

    /// Convert Vision bounding box (normalized, origin bottom-left)
    /// to UIKit/SwiftUI coordinates (origin top-left).
    private func convertBoundingBox(_ box: CGRect, in size: CGSize) -> CGRect {
        let x = box.minX * size.width
        let y = (1 - box.maxY) * size.height
        let width = box.width * size.width
        let height = box.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
