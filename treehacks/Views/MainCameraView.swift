//
//  MainCameraView.swift
//  treehacks
//
//  Created by Dylan Tran on 2/14/26.
//
//  Minimalist camera view designed for a smart-glasses style experience.
//  - Red blinking recording dot (top left)
//  - Purple mic icon for inline voice query (top right)
//  - Voice queries are routed through VoiceAssistant (OpenAI function calling)
//    which can search memories, manage tasks, and look up contacts
//  - Inline result overlay (left side) shows the assistant's response

import SwiftUI
import AVKit
import AVFoundation

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
    @State private var playerLooper: AVPlayerLooper?
    @State private var assistantAnswer: String?
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
                        Text("Processing...")
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

            }
            .padding(.bottom, 20)

            // --- Bottom-left overlay: one sentence, full text, compact width, looped video ---
            if showResult, let answer = assistantAnswer {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(firstSentence(of: answer))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 260, alignment: .leading)

                        if let result = searchResult {
                            Text(result.clip.timeAgoLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        if let player = player {
                            VideoPlayer(player: player)
                                .frame(width: 256, height: 192)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 36)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 312, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(alignment: .topTrailing) {
                        Button(action: dismissResult) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(6)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 12)
                .padding(.bottom, 16)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity
                ))
            }

            if showNoResult {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                    Text("Couldn't process request")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 12)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isListening)
        .animation(.easeInOut(duration: 0.3), value: showResult)
        .animation(.easeInOut(duration: 0.3), value: showNoResult)
        .animation(.easeInOut(duration: 0.3), value: isSearching)
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
            playerLooper = nil
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

            processVoiceQuery(query: finalTranscript)
        }
    }

    // MARK: - Voice Assistant

    private func processVoiceQuery(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSearching else { return }

        isSearching = true
        assistantAnswer = nil

        let clips = snapshotClips
        let assistant = VoiceAssistant(searchEngine: clipManager.searchEngine)

        Task { @MainActor in
            defer { isSearching = false }

            do {
                let response = try await assistant.process(query: trimmed, clips: clips)

                assistantAnswer = response.answer

                // If the assistant found a matching clip, show the video
                if let clipResult = response.clipResult,
                   FileManager.default.fileExists(atPath: clipResult.clip.fileURL.path) {

                    let audioSession = AVAudioSession.sharedInstance()
                    try? audioSession.setCategory(.playback, mode: .default, options: [])
                    try? audioSession.setActive(true)

                    searchResult = clipResult
                    let item = AVPlayerItem(url: clipResult.clip.fileURL)
                    let queuePlayer = AVQueuePlayer(playerItem: item)
                    let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
                    playerLooper = looper
                    player = queuePlayer
                    queuePlayer.play()

                    AppSpeechManager.shared.speak(firstSentence(of: response.answer))
                }

                showResult = true
            } catch {
                print("[MainCameraView] VoiceAssistant error: \(error)")
                showNoResult = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showNoResult = false
                }
            }
        }
    }

    /// First sentence only (up to first . ! ?).
    private func firstSentence(of text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        if let i = t.firstIndex(where: { [".", "!", "?"].contains($0) }) {
            return String(t[...i]).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    // MARK: - Dismiss

    private func dismissResult() {
        AppSpeechManager.shared.stop()
        player?.pause()
        player = nil
        playerLooper = nil
        searchResult = nil
        assistantAnswer = nil
        showResult = false
    }
}
