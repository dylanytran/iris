//
//  MainCameraView.swift
//  treehacks
//
//  Created by Dylan Tran on 2/14/26.
//

import SwiftUI

/// Main camera view that combines:
/// - Live camera preview
/// - Recording status indicator
/// - Memory recall button
/// - Voice query button (semantic search over indexed clips)
struct MainCameraView: View {

    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var recordingManager: RecordingManager
    @ObservedObject var clipManager: ClipManager

    @State private var showMemoryRecall = false
    @State private var showVoiceQuery = false

    var body: some View {
        ZStack {
            // AR camera preview with face recognition labels (full screen)
            ARCameraContainerView(onFrameCaptured: { pixelBuffer, timestamp in
                clipManager.processFrame(pixelBuffer, timestamp: timestamp)
            })
            .ignoresSafeArea()

            // UI Controls overlay
            VStack {
                // Top bar: recording indicator + clip count
                HStack {
                    // Recording indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(recordingManager.isRecording ? Color.red : Color.gray)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .fill(Color.red.opacity(0.5))
                                    .frame(width: 20, height: 20)
                                    .opacity(recordingManager.isRecording ? 1 : 0)
                                    .animation(.easeInOut(duration: 1).repeatForever(), value: recordingManager.isRecording)
                            )

                        Text(recordingManager.isRecording ? "Recording" : "Paused")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())

                    Spacer()

                    // Indexed clips count
                    if clipManager.clipCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "film.stack")
                                .font(.system(size: 12))
                            Text("\(clipManager.clipCount) clips")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

                // Bottom: Action buttons
                HStack(spacing: 16) {
                    // Memory Recall button
                    Button(action: { showMemoryRecall = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Recall")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.blue.opacity(0.85))
                                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        )
                    }

                    // Voice Query button
                    Button(action: { showVoiceQuery = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Ask")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.purple.opacity(0.85))
                                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        )
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            // AR session handles camera preview, face recognition, and frame
            // forwarding via ARCameraContainerView's onFrameCaptured callback.
            // NOTE: AVFoundation recording is disabled while ARKit owns the camera.

            // Start clip indexing
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                clipManager.start()
            }
        }
        .onDisappear {
            clipManager.stop()
        }
        .sheet(isPresented: $showMemoryRecall) {
            MemoryRecallView(recordingManager: recordingManager)
        }
        .sheet(isPresented: $showVoiceQuery) {
            VoiceQueryView(
                clipManager: clipManager,
                cameraManager: cameraManager,
                recordingManager: recordingManager
            )
        }
    }
}
