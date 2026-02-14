//
//  VoiceQueryView.swift
//  treehacks
//
//  Voice-based memory query interface. The user taps a microphone button,
//  asks a question (e.g. "Where did I put my keys?"), and the app finds
//  and plays back the most relevant video clip from the last 60 seconds.
//
//  Designed with large, accessible controls for dementia patients.
//

import SwiftUI
import AVKit

struct VoiceQueryView: View {

    @ObservedObject var clipManager: ClipManager
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var recordingManager: RecordingManager
    @StateObject private var speechRecognizer = SpeechRecognizer()

    @Environment(\.dismiss) private var dismiss

    @State private var searchResult: ClipSearchResult?
    @State private var player: AVPlayer?
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var showNoTranscriptWarning = false
    /// Natural-language answer from OpenAI (when API key is set in Secrets.plist).
    @State private var openAIAnswer: String?
    @State private var isGeneratingAnswer = false
    /// Debug info
    @State private var debugInfo = ""
    /// Snapshot of clips taken at open time (to survive clip manager stop)
    @State private var snapshotClips: [IndexedClip] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Title
                    Text("Ask a Question")
                        .font(.system(size: 28, weight: .bold))
                        .padding(.top, 8)

                    Text("What do you want to remember?")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)

                    // Clip availability indicator
                    HStack(spacing: 8) {
                        Image(systemName: snapshotClips.count > 0 ? "film.stack.fill" : "film.stack")
                            .font(.system(size: 14))
                        Text(snapshotClips.count > 0
                             ? "\(snapshotClips.count) memory clips available"
                             : "No clips recorded yet — go back and let the camera run")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(snapshotClips.count > 0 ? .green : .orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(snapshotClips.count > 0 ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    )
                    .padding(.horizontal)

                    // Microphone button
                    Button(action: toggleListening) {
                        ZStack {
                            Circle()
                                .fill(speechRecognizer.isListening ? Color.red : Color.blue)
                                .frame(width: 100, height: 100)
                                .shadow(color: speechRecognizer.isListening ? .red.opacity(0.4) : .blue.opacity(0.3),
                                        radius: 12, y: 4)

                            Image(systemName: speechRecognizer.isListening ? "stop.fill" : "mic.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.vertical, 8)

                    Text(speechRecognizer.isListening ? "Listening..." : "Tap to speak")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(speechRecognizer.isListening ? .red : .secondary)

                    // No transcript warning
                    if showNoTranscriptWarning {
                        HStack(spacing: 8) {
                            Image(systemName: "ear.trianglebadge.exclamationmark")
                                .foregroundColor(.orange)
                            Text("Couldn't hear you. Please try again.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.orange)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.1))
                        )
                        .padding(.horizontal)
                    }

                    // Transcript
                    if !speechRecognizer.transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You asked:")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)

                            Text("\"\(speechRecognizer.transcript)\"")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .padding(.horizontal)
                    }

                    // Manual search button (fallback if auto-search didn't trigger)
                    if !speechRecognizer.isListening
                        && !speechRecognizer.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && !hasSearched
                        && !isSearching {

                        Button(action: {
                            searchClips(query: speechRecognizer.transcript)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Find Memory")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.green)
                                    .shadow(color: .green.opacity(0.3), radius: 8, y: 4)
                            )
                        }
                    }

                    // Searching indicator
                    if isSearching {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.blue)
                            Text("Searching memories...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }

                    // Results
                    if hasSearched && !isSearching {
                        if let result = searchResult, let player = player {
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 20))
                                    Text("Found a memory!")
                                        .font(.system(size: 18, weight: .semibold))
                                    Spacer()
                                    Text(result.clip.timeAgoLabel)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                }

                                // OpenAI answer (when API key is configured)
                                if isGeneratingAnswer {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.9)
                                        Text("Generating answer...")
                                            .font(.system(size: 15))
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                } else if let answer = openAIAnswer {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Answer")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.secondary)
                                        Text(answer)
                                            .font(.system(size: 17, weight: .medium))
                                            .foregroundColor(.primary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.blue.opacity(0.08))
                                    )
                                }

                                // Video player
                                VideoPlayer(player: player)
                                    .frame(height: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))

                                // Match info
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.clip.description)
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                    Text("Matched via: \(result.method) (score: \(String(format: "%.3f", result.score)))")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                            )
                            .padding(.horizontal)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text("No matching memory found")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("Keep the camera running to record memories")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .padding(.horizontal)
                        }
                    }

                    // Error messages
                    if let error = speechRecognizer.errorMessage {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    // Debug info
                    if !debugInfo.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Debug Log")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(debugInfo)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.tertiarySystemBackground))
                        )
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .onAppear {
                // Snapshot the clips BEFORE stopping the clip manager.
                // This ensures we have clips to search even after stopping.
                snapshotClips = clipManager.indexedClips
                print("[VoiceQueryView] onAppear: \(snapshotClips.count) clips snapshotted")

                // Stop the camera and recording so the microphone is free for speech recognition
                recordingManager.stopRollingRecording()
                clipManager.stop()
                cameraManager.stopSession()

                let embeddedCount = snapshotClips.filter { $0.embedding != nil }.count
                debugInfo = "Clips: \(snapshotClips.count) total, \(embeddedCount) with embeddings"
                debugInfo += "\nSearch engine: \(clipManager.searchEngine.isAvailable ? "Ready" : "UNAVAILABLE")"

                speechRecognizer.requestPermissions()

                // Wire up the onFinished callback — this is the PRIMARY trigger for search.
                // It fires directly when speech recognition stops (no SwiftUI reactivity needed).
                speechRecognizer.onFinished = { [self] finalTranscript in
                    print("[VoiceQueryView] onFinished callback, transcript=\"\(finalTranscript)\"")
                    debugInfo += "\nSpeech finished. Transcript: \"\(finalTranscript)\""

                    if finalTranscript.isEmpty {
                        showNoTranscriptWarning = true
                        debugInfo += "\n⚠️ Empty transcript"
                    } else {
                        showNoTranscriptWarning = false
                        // Trigger search immediately
                        searchClips(query: finalTranscript)
                    }
                }
            }
            .onDisappear {
                print("[VoiceQueryView] onDisappear")
                player?.pause()
                player = nil
                speechRecognizer.onFinished = nil
                speechRecognizer.stopListening()

                // Restart the camera and recording when returning to the camera view
                cameraManager.configure()
                cameraManager.startSession()

                // Re-start recording and clip managers
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    recordingManager.startRollingRecording()
                    clipManager.start()
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleListening() {
        if speechRecognizer.isListening {
            print("[VoiceQueryView] User tapped stop")
            speechRecognizer.stopListening()
        } else {
            print("[VoiceQueryView] User tapped start")
            // Reset previous results
            searchResult = nil
            player?.pause()
            player = nil
            hasSearched = false
            openAIAnswer = nil
            showNoTranscriptWarning = false

            // Update debug info with current clip state
            let embeddedCount = snapshotClips.filter { $0.embedding != nil }.count
            debugInfo = "Clips: \(snapshotClips.count) total, \(embeddedCount) with embeddings"
            debugInfo += "\nSearch engine: \(clipManager.searchEngine.isAvailable ? "Ready" : "UNAVAILABLE")"
            debugInfo += "\nStarting speech recognition..."

            speechRecognizer.startListening()

            // Auto-stop after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak speechRecognizer] in
                guard let sr = speechRecognizer, sr.isListening else { return }
                print("[VoiceQueryView] Auto-stopping after 10s")
                sr.stopListening()
            }
        }
    }

    private func searchClips(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            debugInfo += "\n⚠️ searchClips called with empty query"
            return
        }
        guard !isSearching else {
            debugInfo += "\n⚠️ Search already in progress"
            return
        }

        print("[VoiceQueryView] searchClips called with: \"\(trimmedQuery)\"")
        isSearching = true
        openAIAnswer = nil

        let clips = snapshotClips
        debugInfo += "\nSearching \(clips.count) clips for: \"\(trimmedQuery)\""

        // Run search on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            let searchEngine = clipManager.searchEngine
            let result = searchEngine.findBestClip(for: trimmedQuery, in: clips)

            // Build debug scores
            let allScores = searchEngine.scoreAllClips(for: trimmedQuery, in: clips)
            var scoreLog = ""
            for (i, scored) in allScores.prefix(5).enumerated() {
                let kw = scored.clip.keywords.prefix(3).joined(separator: ", ")
                scoreLog += "\n  #\(i): score=\(String(format: "%.3f", scored.score)) method=\(scored.clip.embedding != nil ? "emb" : "none") [\(kw)]"
            }

            DispatchQueue.main.async {
                isSearching = false
                hasSearched = true

                let resultMethod = result?.method ?? "nil"
                let resultScore = result?.score ?? 0
                debugInfo += "\nResult: \(resultMethod) score=\(String(format: "%.3f", resultScore))"
                debugInfo += "\nTop scores:" + scoreLog
                print("[VoiceQueryView] Search result: method=\(resultMethod) score=\(String(format: "%.3f", resultScore))")

                if let result = result {
                    // Verify clip file exists
                    let fileExists = FileManager.default.fileExists(atPath: result.clip.fileURL.path)
                    debugInfo += "\nFile: \(result.clip.fileURL.lastPathComponent) exists=\(fileExists)"
                    print("[VoiceQueryView] Clip file: \(result.clip.fileURL.lastPathComponent) exists=\(fileExists)")

                    if fileExists {
                        // Set audio session to playback BEFORE creating the player
                        let audioSession = AVAudioSession.sharedInstance()
                        do {
                            try audioSession.setCategory(.playback, mode: .default, options: [])
                            try audioSession.setActive(true)
                            print("[VoiceQueryView] Audio session set to playback")
                        } catch {
                            print("[VoiceQueryView] Failed to set playback audio session: \(error)")
                            debugInfo += "\n⚠️ Audio session error: \(error.localizedDescription)"
                        }

                        searchResult = result
                        let avPlayer = AVPlayer(url: result.clip.fileURL)
                        self.player = avPlayer
                        avPlayer.play()
                        print("[VoiceQueryView] Playing clip")

                        // Generate natural-language answer via OpenAI when API key is set
                        let queryForAI = trimmedQuery
                        Task { @MainActor in
                            isGeneratingAnswer = true
                            defer { isGeneratingAnswer = false }
                            do {
                                if let answer = try await OpenAIClient.generateAnswer(
                                    memory: result.clip.description,
                                    question: queryForAI
                                ) {
                                    openAIAnswer = answer
                                }
                            } catch {
                                // No answer shown; user still has the video and clip description
                                print("[VoiceQueryView] OpenAI error: \(error)")
                            }
                        }
                    } else {
                        debugInfo += "\n❌ ERROR: Clip file was deleted!"
                        searchResult = nil
                        player = nil
                    }
                } else {
                    searchResult = nil
                    player = nil
                    debugInfo += "\n❌ No clips available to search"
                    print("[VoiceQueryView] No clips to search")
                }
            }
        }
    }
}
