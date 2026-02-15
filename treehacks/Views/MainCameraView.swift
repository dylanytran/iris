//
//  MainCameraView.swift
//  treehacks
//
//  Created by Dylan Tran on 2/14/26.
//
//  Minimalist camera view designed for a smart-glasses style experience.
//  - Red blinking recording dot (top left)
//  - Purple mic icon for inline voice query (top right)
//  - Inline result overlay (left side) when a memory clip is found

import SwiftUI
import AVKit

struct MainCameraView: View {

    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var recordingManager: RecordingManager
    @ObservedObject var clipManager: ClipManager

    // MARK: - Inline voice query state
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isListening = false
    @State private var isSearching = false
    @State private var searchResult: ClipSearchResult?
    @State private var player: AVPlayer?
    @State private var openAIAnswer: String?
    @State private var isGeneratingAnswer = false
    @State private var snapshotClips: [IndexedClip] = []
    @State private var showResult = false
    @State private var showNoResult = false

    // Blinking animation
    @State private var dotVisible = true

    var body: some View {
        ZStack {
            // Full-screen AR camera preview
            ARCameraContainerView(onFrameCaptured: { pixelBuffer, timestamp in
                clipManager.processFrame(pixelBuffer, timestamp: timestamp)
            })
            .ignoresSafeArea()

            // --- UI Overlay ---
            VStack {
                // Top bar: recording dot (left) + mic button (right)
                HStack {
                    // Red blinking recording dot
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .opacity(dotVisible ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dotVisible)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                        .onAppear { dotVisible = false }

                    Spacer()

                    // Purple mic button for inline voice query
                    Button(action: handleMicTap) {
                        ZStack {
                            Circle()
                                .fill(isListening ? Color.red.opacity(0.85) : Color.purple.opacity(0.85))
                                .frame(width: 36, height: 36)
                                .shadow(color: isListening ? .red.opacity(0.5) : .purple.opacity(0.4), radius: 8)

                            Image(systemName: isListening ? "stop.fill" : "mic.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Listening indicator (subtle text below top bar)
                if isListening {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 6, height: 6)
                        Text(speechRecognizer.transcript.isEmpty ? "Listening..." : "\"\(speechRecognizer.transcript)\"")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 4)
                }

                // Searching indicator
                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                        Text("Searching memories...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
                    .padding(.top, 4)
                }

                Spacer()

                // --- Inline result overlay (left side) ---
                if showResult, let result = searchResult, let player = player {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            // Answer text above the video
                            if isGeneratingAnswer {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.7)
                                    Text("Thinking...")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                            } else if let answer = openAIAnswer {
                                Text(answer)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            // Time ago badge
                            Text(result.clip.timeAgoLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))

                            // Video player
                            VideoPlayer(player: player)
                                .frame(width: 160, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(alignment: .topTrailing) {
                            // Dismiss button
                            Button(action: dismissResult) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(6)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .opacity
                    ))
                }

                // No result message
                if showNoResult {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                        Text("No matching memory found")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
                    .padding(.bottom, 8)
                }
            }
            .padding(.bottom, 20)
            .animation(.easeInOut(duration: 0.25), value: isListening)
            .animation(.easeInOut(duration: 0.3), value: showResult)
            .animation(.easeInOut(duration: 0.3), value: showNoResult)
            .animation(.easeInOut(duration: 0.3), value: isSearching)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                clipManager.start()
            }
            speechRecognizer.requestPermissions()
            setupSpeechCallback()
        }
        .onDisappear {
            clipManager.stop()
            speechRecognizer.onFinished = nil
            speechRecognizer.stopListening()
            player?.pause()
            player = nil
        }
    }

    // MARK: - Mic Actions

    private func handleMicTap() {
        if isListening {
            speechRecognizer.stopListening()
        } else {
            startInlineQuery()
        }
    }

    private func startInlineQuery() {
        // Reset previous state
        dismissResult()
        showNoResult = false

        // Snapshot clips before stopping
        snapshotClips = clipManager.indexedClips
        print("[MainCameraView] Snapshotted \(snapshotClips.count) clips for search")

        // Start listening
        speechRecognizer.startListening()
        isListening = true

        // Auto-stop after 8 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak speechRecognizer] in
            guard let sr = speechRecognizer, sr.isListening else { return }
            sr.stopListening()
        }
    }

    private func setupSpeechCallback() {
        speechRecognizer.onFinished = { finalTranscript in
            print("[MainCameraView] Speech finished: \"\(finalTranscript)\"")
            isListening = false

            if finalTranscript.isEmpty {
                return
            }

            searchClips(query: finalTranscript)
        }
    }

    // MARK: - Search

    private func searchClips(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSearching else { return }

        isSearching = true
        openAIAnswer = nil

        let clips = snapshotClips

        DispatchQueue.global(qos: .userInitiated).async {
            let result = clipManager.searchEngine.findBestClip(for: trimmed, in: clips)

            DispatchQueue.main.async {
                isSearching = false

                if let result = result,
                   FileManager.default.fileExists(atPath: result.clip.fileURL.path) {

                    // Set audio to playback
                    let audioSession = AVAudioSession.sharedInstance()
                    try? audioSession.setCategory(.playback, mode: .default, options: [])
                    try? audioSession.setActive(true)

                    searchResult = result
                    let avPlayer = AVPlayer(url: result.clip.fileURL)
                    player = avPlayer
                    avPlayer.play()
                    showResult = true

                    // Generate AI answer
                    Task { @MainActor in
                        isGeneratingAnswer = true
                        defer { isGeneratingAnswer = false }
                        do {
                            if let answer = try await OpenAIClient.generateAnswer(
                                memory: result.clip.description,
                                question: trimmed
                            ) {
                                openAIAnswer = answer
                            }
                        } catch {
                            print("[MainCameraView] OpenAI error: \(error)")
                        }
                    }
                } else {
                    showNoResult = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showNoResult = false
                    }
                }
            }
        }
    }

    // MARK: - Dismiss

    private func dismissResult() {
        player?.pause()
        player = nil
        searchResult = nil
        openAIAnswer = nil
        showResult = false
        isGeneratingAnswer = false
    }
}
