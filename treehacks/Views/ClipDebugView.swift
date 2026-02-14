//
//  ClipDebugView.swift
//  treehacks
//
//  Debug view that displays all indexed video clips with their
//  keywords, descriptions, embeddings status, and playable video.
//  Useful for testing the clip indexing pipeline.
//

import SwiftUI
import AVKit

struct ClipDebugView: View {

    @ObservedObject var clipManager: ClipManager

    @State private var selectedClip: IndexedClip?
    @State private var player: AVPlayer?
    @State private var autoRefreshTimer: Timer?

    var body: some View {
        NavigationStack {
            List {
                // Summary section
                Section {
                    HStack {
                        Text("Total Clips")
                        Spacer()
                        Text("\(clipManager.indexedClips.count)")
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    HStack {
                        Text("Clip Indexing")
                        Spacer()
                        Text(clipManager.isActive ? "Active" : "Paused")
                            .fontWeight(.semibold)
                            .foregroundColor(clipManager.isActive ? .green : .orange)
                    }
                    HStack {
                        Text("Search Engine")
                        Spacer()
                        Text(clipManager.searchEngine.isAvailable ? "Ready" : "Unavailable")
                            .fontWeight(.semibold)
                            .foregroundColor(clipManager.searchEngine.isAvailable ? .green : .red)
                    }
                } header: {
                    Text("Status")
                }

                // Selected clip player
                if let clip = selectedClip, let player = player {
                    Section {
                        VStack(spacing: 8) {
                            VideoPlayer(player: player)
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text(clip.description)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } header: {
                        Text("Now Playing")
                    }
                }

                // All clips
                Section {
                    if clipManager.indexedClips.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "film.stack")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary)
                            Text("No clips indexed yet")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Go to the Camera tab and wait 5+ seconds for clips to appear here.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(Array(clipManager.indexedClips.enumerated().reversed()), id: \.element.id) { index, clip in
                            ClipRow(clip: clip, index: index, onPlay: {
                                playClip(clip)
                            })
                        }
                    }
                } header: {
                    HStack {
                        Text("Indexed Clips (\(clipManager.indexedClips.count))")
                        Spacer()
                        if !clipManager.indexedClips.isEmpty {
                            Text("Newest first")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Clip Debug")
            .onDisappear {
                player?.pause()
            }
        }
    }

    private func playClip(_ clip: IndexedClip) {
        player?.pause()
        let avPlayer = AVPlayer(url: clip.fileURL)
        player = avPlayer
        selectedClip = clip
        avPlayer.play()
    }
}

// MARK: - Clip Row

struct ClipRow: View {
    let clip: IndexedClip
    let index: Int
    let onPlay: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: index, time, play button
            HStack {
                // Clip number
                Text("#\(index)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue))

                // Time info
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.timeAgoLabel)
                        .font(.system(size: 15, weight: .semibold))
                    Text(formatTimeRange(clip.startTime, clip.endTime))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Play button
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Description:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(clip.description)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemBackground))
            )

            // Keywords (expandable)
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Text("Keywords (\(clip.keywords.count))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.blue)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                    Spacer()

                    // Embedding status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(clip.embedding != nil ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(clip.embedding != nil ? "Embedded" : "No embedding")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                FlowLayout(spacing: 6) {
                    ForEach(clip.keywords.sorted(), id: \.self) { keyword in
                        Text(keyword)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.blue.opacity(0.12))
                            )
                    }
                }
            }

            // File info
            Text(clip.fileURL.lastPathComponent)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.vertical, 6)
    }

    private func formatTimeRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "\(formatter.string(from: start)) → \(formatter.string(from: end))"
    }
}

// MARK: - Flow Layout (wrapping keyword tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
