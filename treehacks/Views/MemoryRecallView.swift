//
//  MemoryRecallView.swift
//  treehacks
//
//  Created by Dylan Tran on 2/14/26.
//

import SwiftUI
import AVKit

/// Allows the user to go back in time and replay recorded footage.
/// Features a large, accessible time selector and video player.
struct MemoryRecallView: View {

    @ObservedObject var recordingManager: RecordingManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMinutesAgo: Double = 1
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var noRecordingAvailable = false

    private var maxMinutes: Double {
        max(1, recordingManager.maxRecallSeconds / 60.0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                Text("What did you see?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.top, 8)

                // Time selector
                VStack(spacing: 16) {
                    Text("Go back")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.secondary)

                    // Large time display
                    Text(timeLabel)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: selectedMinutesAgo)

                    Text("ago")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.secondary)

                    // Time slider
                    VStack(spacing: 8) {
                        Slider(
                            value: $selectedMinutesAgo,
                            in: 0.5...maxMinutes,
                            step: 0.5
                        )
                        .tint(.blue)
                        .padding(.horizontal)

                        HStack {
                            Text("30s ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(maxMinutes))m ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Quick select buttons
                    HStack(spacing: 12) {
                        ForEach([0.5, 1.0, 2.0, 5.0], id: \.self) { minutes in
                            Button(action: { selectedMinutesAgo = min(minutes, maxMinutes) }) {
                                Text(minutes < 1 ? "30s" : "\(Int(minutes))m")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(selectedMinutesAgo == minutes ? .white : .blue)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedMinutesAgo == minutes ? Color.blue : Color.blue.opacity(0.1))
                                    )
                            }
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                )
                .padding(.horizontal)

                // Video player
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                        .onDisappear {
                            player.pause()
                        }
                } else if noRecordingAvailable {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No recording available for this time")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Keep the camera running to build up memory")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal)
                }

                // Play button
                Button(action: playRecording) {
                    HStack(spacing: 10) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 20))
                        Text(isPlaying ? "Stop" : "Play Memory")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue)
                    )
                }
                .padding(.horizontal)

                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }

    private var timeLabel: String {
        let totalSeconds = Int(selectedMinutesAgo * 60)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 && seconds > 0 {
            return "\(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes) min"
        } else {
            return "\(seconds)s"
        }
    }

    private func playRecording() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }

        let secondsAgo = selectedMinutesAgo * 60
        guard let recording = recordingManager.getRecording(secondsAgo: secondsAgo) else {
            noRecordingAvailable = true
            return
        }

        noRecordingAvailable = false
        let avPlayer = AVPlayer(url: recording.url)

        // Seek to the correct position within the segment
        let seekTime = CMTime(seconds: recording.seekTime, preferredTimescale: 600)
        avPlayer.seek(to: seekTime) { _ in
            avPlayer.play()
        }

        self.player = avPlayer
        self.isPlaying = true

        // Observe when playback ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            self.isPlaying = false
        }
    }
}
