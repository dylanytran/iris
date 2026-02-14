//
//  CameraManager.swift
//  treehacks
//
//  Created by Dylan Tran on 2/14/26.
//

import AVFoundation
import UIKit
import Combine

/// Manages the AVCaptureSession with dual outputs:
/// - AVCaptureVideoDataOutput for real-time frame processing (face detection)
/// - AVCaptureMovieFileOutput for rolling video recording
class CameraManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isSessionRunning = false
    @Published var error: String?

    // MARK: - Capture Session

    let session = AVCaptureSession()
    let movieFileOutput = AVCaptureMovieFileOutput()

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.treehacks.sessionQueue")
    private let processingQueue = DispatchQueue(label: "com.treehacks.processingQueue", qos: .userInitiated)

    // MARK: - Frame Callback

    /// Called on every captured video frame for face detection processing.
    var onFrameCaptured: ((CVPixelBuffer, CMTime) -> Void)?

    // MARK: - Recording Delegate

    /// Set this to the RecordingManager to receive recording callbacks.
    weak var recordingDelegate: AVCaptureFileOutputRecordingDelegate?

    // MARK: - Setup

    /// Whether the session has already been configured (inputs/outputs added).
    private var isConfigured = false

    func configure() {
        sessionQueue.async { [weak self] in
            self?.setupSession()
        }
    }

    private func setupSession() {
        // Only add inputs/outputs once. Calling configure() again just ensures
        // the delegate is still wired. This prevents duplicate input/output errors.
        guard !isConfigured else {
            // Re-ensure the delegate is set (in case it was cleared)
            videoDataOutput.setSampleBufferDelegate(self, queue: processingQueue)
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        // --- Camera Input ---
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            DispatchQueue.main.async { self.error = "No back camera available" }
            session.commitConfiguration()
            return
        }

        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(cameraInput) {
                session.addInput(cameraInput)
            }
        } catch {
            DispatchQueue.main.async { self.error = "Cannot access camera: \(error.localizedDescription)" }
            session.commitConfiguration()
            return
        }

        // --- Microphone Input ---
        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic) {
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
        }

        // --- Video Data Output (for frame processing) ---
        videoDataOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }

        // --- Movie File Output (for recording) ---
        if session.canAddOutput(movieFileOutput) {
            session.addOutput(movieFileOutput)
        }

        session.commitConfiguration()
        isConfigured = true
    }

    // MARK: - Session Control

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    // MARK: - Recording Control

    func startRecording(to url: URL) {
        guard let delegate = recordingDelegate else { return }
        if movieFileOutput.isRecording { return }
        movieFileOutput.startRecording(to: url, recordingDelegate: delegate)
    }

    func stopRecording() {
        if movieFileOutput.isRecording {
            movieFileOutput.stopRecording()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrameCaptured?(pixelBuffer, timestamp)
    }
}
