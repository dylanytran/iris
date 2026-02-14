//
//  AddPersonView.swift
//  treehacks
//
//  Created by Dylan Tran on 2/14/26.
//

import SwiftUI
import SwiftData
import AVFoundation
import Vision

/// View for registering a new person.
/// Captures the person's face from the camera, extracts facial landmarks,
/// and saves a profile with name, relationship, and notes.
struct AddPersonView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var cameraManager: CameraManager

    @State private var name = ""
    @State private var relationship = ""
    @State private var notes = ""
    @State private var capturedImage: UIImage?
    @State private var faceDescriptor: [Float]?
    @State private var showCamera = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Face capture section
                    VStack(spacing: 16) {
                        Text("Face Photo")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let image = capturedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 160, height: 160)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.blue, lineWidth: 3))
                                .overlay(alignment: .bottomTrailing) {
                                    if faceDescriptor != nil {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 28))
                                            .foregroundColor(.green)
                                            .background(Circle().fill(.white).frame(width: 24, height: 24))
                                    }
                                }

                            Button("Retake Photo") {
                                showCamera = true
                            }
                            .font(.system(size: 16, weight: .medium))
                        } else {
                            Button(action: { showCamera = true }) {
                                VStack(spacing: 12) {
                                    Image(systemName: "camera.circle.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.blue)
                                    Text("Take Face Photo")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.blue)
                                    Text("Position their face in the center")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                                )
                            }
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                    )

                    // Info section
                    VStack(spacing: 16) {
                        Text("Person Info")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 12) {
                            TextField("Name", text: $name)
                                .font(.system(size: 18))
                                .textFieldStyle(.roundedBorder)

                            TextField("Relationship (e.g., Daughter, Friend)", text: $relationship)
                                .font(.system(size: 16))
                                .textFieldStyle(.roundedBorder)

                            TextField("Notes (e.g., Visits on Sundays)", text: $notes)
                                .font(.system(size: 16))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                    )

                    // Save button
                    Button(action: savePerson) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Save Person")
                                .font(.system(size: 20, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(canSave ? Color.blue : Color.gray)
                        )
                    }
                    .disabled(!canSave)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCamera) {
                FaceCaptureView(
                    capturedImage: $capturedImage,
                    faceDescriptor: $faceDescriptor,
                    errorMessage: $errorMessage,
                    cameraManager: cameraManager
                )
            }
        }
    }

    private var canSave: Bool {
        !name.isEmpty && capturedImage != nil && !isSaving
    }

    private func savePerson() {
        isSaving = true

        let person = Person(
            name: name,
            relationship: relationship,
            notes: notes,
            faceImageData: capturedImage?.jpegData(compressionQuality: 0.8)
        )
        person.faceDescriptor = faceDescriptor

        modelContext.insert(person)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            isSaving = false
        }
    }
}

// MARK: - Face Capture State (thread-safe)

/// Holds the latest camera frame and face detection state.
/// Accessed from both the camera processing queue and the main thread.
class FaceCaptureState: ObservableObject {
    /// Latest pixel buffer from camera (set on processing queue, read on main thread for capture)
    private let lock = NSLock()
    private var _latestFrame: CVPixelBuffer?

    var latestFrame: CVPixelBuffer? {
        get { lock.withLock { _latestFrame } }
        set { lock.withLock { _latestFrame = newValue } }
    }

    @Published var detectedFaceRect: CGRect?
    @Published var isProcessing = false

    func detectFaceForGuide(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])

        do {
            try handler.perform([request])
        } catch { return }

        let faceRect = request.results?.first?.boundingBox

        DispatchQueue.main.async { [weak self] in
            self?.detectedFaceRect = faceRect
        }
    }
}

// MARK: - Face Capture View

/// Camera view specifically for capturing a face photo during registration.
struct FaceCaptureView: View {

    @Binding var capturedImage: UIImage?
    @Binding var faceDescriptor: [Float]?
    @Binding var errorMessage: String?
    @ObservedObject var cameraManager: CameraManager

    @Environment(\.dismiss) private var dismiss
    @StateObject private var captureState = FaceCaptureState()

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            // Face guide overlay
            VStack {
                Spacer()

                // Face guide circle
                Circle()
                    .stroke(
                        captureState.detectedFaceRect != nil ? Color.green : Color.white.opacity(0.6),
                        lineWidth: 3
                    )
                    .frame(width: 250, height: 250)

                Spacer()

                // Instructions
                Text(captureState.detectedFaceRect != nil
                     ? "Face detected! Tap capture."
                     : "Position face in the circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())

                // Capture button
                Button(action: capturePhoto) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 72, height: 72)
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 82, height: 82)
                    }
                }
                .disabled(captureState.isProcessing)
                .padding(.bottom, 30)
            }

            if captureState.isProcessing {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                ProgressView("Processing face...")
                    .tint(.white)
                    .foregroundColor(.white)
                    .font(.headline)
            }
        }
        .onAppear {
            // Set up face detection on frames for the guide
            let state = captureState
            cameraManager.onFrameCaptured = { pixelBuffer, _ in
                state.latestFrame = pixelBuffer
                state.detectFaceForGuide(in: pixelBuffer)
            }
        }
        .onDisappear {
            cameraManager.onFrameCaptured = nil
        }
    }

    private func capturePhoto() {
        guard let pixelBuffer = captureState.latestFrame else {
            errorMessage = "No camera frame available"
            return
        }

        captureState.isProcessing = true

        DispatchQueue.global(qos: .userInitiated).async {
            // Detect face and landmarks
            let landmarksRequest = VNDetectFaceLandmarksRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])

            do {
                try handler.perform([landmarksRequest])
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Face detection failed"
                    captureState.isProcessing = false
                }
                return
            }

            guard let results = landmarksRequest.results,
                  let face = results.first,
                  let landmarks = face.landmarks else {
                DispatchQueue.main.async {
                    errorMessage = "No face detected. Please try again."
                    captureState.isProcessing = false
                }
                return
            }

            // Extract face descriptor
            let descriptor = FaceRecognitionService.extractDescriptor(from: landmarks)

            // Convert pixel buffer to UIImage and crop to face
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                DispatchQueue.main.async {
                    errorMessage = "Failed to capture image"
                    captureState.isProcessing = false
                }
                return
            }

            let fullImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

            // Crop to face region with padding
            let faceRect = face.boundingBox
            let imageSize = fullImage.size
            let padding: CGFloat = 30
            let facePixelRect = CGRect(
                x: faceRect.minX * imageSize.width - padding,
                y: (1 - faceRect.maxY) * imageSize.height - padding,
                width: faceRect.width * imageSize.width + padding * 2,
                height: faceRect.height * imageSize.height + padding * 2
            ).intersection(CGRect(origin: .zero, size: imageSize))

            let croppedImage: UIImage
            if let cropped = fullImage.cgImage?.cropping(to: facePixelRect) {
                croppedImage = UIImage(cgImage: cropped)
            } else {
                croppedImage = fullImage
            }

            DispatchQueue.main.async {
                capturedImage = croppedImage
                faceDescriptor = descriptor
                captureState.isProcessing = false

                if descriptor == nil {
                    errorMessage = "Could not extract face features. Try with better lighting."
                } else {
                    errorMessage = nil
                    dismiss()
                }
            }
        }
    }
}
