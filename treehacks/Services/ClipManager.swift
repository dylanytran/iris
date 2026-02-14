//
//  ClipManager.swift
//  treehacks
//
//  Records 5-second video clips using AVAssetWriter, analyzes frames
//  with FrameAnalyzer for keywords, and indexes clips with NLEmbedding
//  vectors for semantic search. Keeps the last 60 seconds of clips.
//

import AVFoundation
import Combine

final class ClipManager: ObservableObject {

    // MARK: - Configuration

    /// Duration of each clip in seconds.
    let clipDuration: TimeInterval = 6

    /// Maximum total history to keep in seconds.
    let maxHistory: TimeInterval = 60

    /// Analyze a frame every N frames for keywords.
    let analyzeEveryNFrames = 10

    // MARK: - Published State

    @Published var indexedClips: [IndexedClip] = []
    @Published var isActive = false
    @Published var clipCount: Int = 0

    // MARK: - Dependencies

    let searchEngine = ClipSearchEngine()
    private let frameAnalyzer = FrameAnalyzer()

    // MARK: - AVAssetWriter State

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var currentClipStartTime: Date?
    private var sessionStartTimestamp: CMTime?
    private var isWritingClip = false
    private var frameCount = 0

    // Accumulated keywords for the current clip being recorded
    private var currentKeywords = Set<String>()

    /// Number of frames to capture per clip for GPT-4o-mini vision analysis.
    private let visionFrameCount = 3

    /// JPEG snapshots of representative frames for GPT-4o-mini vision analysis.
    /// Captured at 25%, 50%, and 75% of the clip duration.
    private var representativeFrameJPEGs: [Data] = []
    /// Tracks which capture points (1/4, 2/4, 3/4) have already been taken.
    private var nextCaptureIndex = 0

    // Serial queue for all writing operations (thread safety)
    private let writerQueue = DispatchQueue(label: "com.treehacks.clipWriter", qos: .userInitiated)

    // MARK: - Clips Directory

    private let clipsDirectory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        clipsDirectory = docs.appendingPathComponent("searchable_clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        cleanupAllClips()
    }

    // MARK: - Lifecycle

    func start() {
        isActive = true
    }

    func stop() {
        isActive = false
        writerQueue.async { [weak self] in
            self?.finalizeCurrentClip()
        }
    }

    // MARK: - Frame Processing (called from camera callback)

    /// Process a video frame: write to clip, analyze for keywords.
    /// Call this from the camera frame callback (runs on writerQueue internally).
    func processFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard isActive else { return }

        writerQueue.async { [weak self] in
            guard let self = self else { return }

            // Start a new clip if none is active
            if !self.isWritingClip {
                self.startNewClip(firstFrame: pixelBuffer, timestamp: timestamp)
            }

            // Rotate clip if duration exceeded
            if let start = self.currentClipStartTime,
               Date().timeIntervalSince(start) >= self.clipDuration {
                self.finalizeCurrentClip()
                self.startNewClip(firstFrame: pixelBuffer, timestamp: timestamp)
            }

            // Write frame to current clip
            self.writeFrame(pixelBuffer, timestamp: timestamp)

            // Analyze every Nth frame for keywords
            self.frameCount += 1
            if self.frameCount % self.analyzeEveryNFrames == 0 {
                let labels = self.frameAnalyzer.classifyFrame(pixelBuffer)
                self.currentKeywords.formUnion(labels)

                // Also try to recognize visible text
                let textLabels = self.frameAnalyzer.recognizeText(in: pixelBuffer)
                for text in textLabels {
                    self.currentKeywords.insert("text: \(text)")
                }
            }

            // Capture representative frames at 25%, 50%, and 75% of the clip
            // (for GPT-4o-mini vision analysis after the clip is finalized)
            if self.nextCaptureIndex < self.visionFrameCount,
               let start = self.currentClipStartTime {
                // Capture points: 1/4, 2/4, 3/4 of clipDuration
                let captureTime = self.clipDuration * Double(self.nextCaptureIndex + 1) / Double(self.visionFrameCount + 1)
                if Date().timeIntervalSince(start) >= captureTime {
                    if let jpeg = self.frameAnalyzer.pixelBufferToJPEG(pixelBuffer) {
                        self.representativeFrameJPEGs.append(jpeg)
                    }
                    self.nextCaptureIndex += 1
                }
            }
        }
    }

    // MARK: - Search

    /// Find the best clip matching a user query (with embedding → keyword → recent fallbacks).
    func findBestClip(for query: String) -> ClipSearchResult? {
        searchEngine.findBestClip(for: query, in: indexedClips)
    }

    /// Score all clips against a query (for debug display).
    func scoreAllClips(for query: String) -> [(clip: IndexedClip, score: Double)] {
        searchEngine.scoreAllClips(for: query, in: indexedClips)
    }

    // MARK: - AVAssetWriter Management

    private func startNewClip(firstFrame pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        let fileName = "clip_\(Int(Date().timeIntervalSince1970 * 1000)).mov"
        let clipURL = clipsDirectory.appendingPathComponent(fileName)

        do {
            let writer = try AVAssetWriter(url: clipURL, fileType: .mov)

            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            let outputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 800_000,
                    AVVideoMaxKeyFrameIntervalKey: 30,
                ]
            ]

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            input.expectsMediaDataInRealTime = true
            input.transform = CGAffineTransform(rotationAngle: .pi / 2) // Portrait

            let pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
            )

            guard writer.canAdd(input) else {
                print("ClipManager: Cannot add video input to writer")
                return
            }

            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: timestamp)

            self.assetWriter = writer
            self.videoInput = input
            self.adaptor = pixelAdaptor
            self.currentClipStartTime = Date()
            self.sessionStartTimestamp = timestamp
            self.isWritingClip = true
            self.currentKeywords = []
            self.frameCount = 0
            self.representativeFrameJPEGs = []
            self.nextCaptureIndex = 0

        } catch {
            print("ClipManager: Failed to create AVAssetWriter: \(error)")
        }
    }

    private func writeFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard isWritingClip,
              let input = videoInput,
              let adaptor = adaptor,
              input.isReadyForMoreMediaData else { return }

        adaptor.append(pixelBuffer, withPresentationTime: timestamp)
    }

    private func finalizeCurrentClip() {
        guard isWritingClip, let writer = assetWriter else { return }

        isWritingClip = false

        let keywords = currentKeywords
        let startTime = currentClipStartTime ?? Date()
        let endTime = Date()
        let clipURL = writer.outputURL
        let frameJPEGs = representativeFrameJPEGs  // Capture for async use

        videoInput?.markAsFinished()

        writer.finishWriting { [weak self] in
            guard let self = self else { return }

            guard writer.status == .completed else {
                print("[ClipManager] Writer finished with status \(writer.status.rawValue)")
                if let error = writer.error {
                    print("[ClipManager] Writer error: \(error)")
                }
                return
            }

            // Build initial description from on-device Vision keywords
            let descriptionParts = keywords.sorted()
            let description: String
            if descriptionParts.isEmpty {
                description = "video clip"
            } else {
                description = "I see " + descriptionParts.joined(separator: ", ")
            }

            // Compute NLEmbedding vector for the initial description
            let embedding = self.searchEngine.computeEmbedding(for: description)

            let clip = IndexedClip(
                fileURL: clipURL,
                startTime: startTime,
                endTime: endTime,
                keywords: keywords,
                description: description,
                embedding: embedding
            )

            DispatchQueue.main.async {
                self.indexedClips.append(clip)
                self.clipCount = self.indexedClips.count
                self.pruneOldClips()

                // Asynchronously enhance keywords with GPT-4o-mini vision (3 frames in one call)
                if !frameJPEGs.isEmpty, OpenAIClient.hasAPIKey {
                    self.enhanceClipWithVision(clipID: clip.id, jpegImages: frameJPEGs, existingKeywords: keywords)
                }
            }
        }

        // Clear writer references
        self.assetWriter = nil
        self.videoInput = nil
        self.adaptor = nil
    }

    // MARK: - GPT-4o-mini Vision Enhancement

    /// Sends representative frames to GPT-4o-mini (all in one API call) and upgrades
    /// the clip's keywords, description, and embedding when the response comes back.
    private func enhanceClipWithVision(clipID: UUID, jpegImages: [Data], existingKeywords: Set<String>) {
        print("[ClipManager] Requesting GPT-4o-mini vision for clip \(clipID.uuidString.prefix(8)) with \(jpegImages.count) frame(s)...")

        Task {
            do {
                guard let aiKeywords = try await OpenAIClient.describeImages(jpegImages) else {
                    print("[ClipManager] Vision returned nil for clip \(clipID.uuidString.prefix(8))")
                    return
                }

                // Merge AI keywords with existing on-device keywords
                var mergedKeywords = existingKeywords
                for kw in aiKeywords {
                    mergedKeywords.insert(kw)
                }

                // Build an improved description prioritizing the AI keywords
                let aiDescription = "I see " + aiKeywords.joined(separator: ", ")
                let fullDescription: String
                if existingKeywords.isEmpty {
                    fullDescription = aiDescription
                } else {
                    // AI keywords first (more accurate), then Vision keywords
                    let visionPart = existingKeywords.sorted().joined(separator: ", ")
                    fullDescription = aiDescription + "; also: " + visionPart
                }

                // Recompute embedding with the richer description
                let newEmbedding = self.searchEngine.computeEmbedding(for: fullDescription)

                // Capture as let for concurrency safety
                let finalKeywords = mergedKeywords

                // Update the clip on the main thread
                await MainActor.run {
                    if let index = self.indexedClips.firstIndex(where: { $0.id == clipID }) {
                        self.indexedClips[index].keywords = finalKeywords
                        self.indexedClips[index].description = fullDescription
                        self.indexedClips[index].embedding = newEmbedding
                        print("[ClipManager] Enhanced clip \(clipID.uuidString.prefix(8)) with \(aiKeywords.count) AI keywords")
                    } else {
                        print("[ClipManager] Clip \(clipID.uuidString.prefix(8)) was pruned before enhancement arrived")
                    }
                }
            } catch {
                print("[ClipManager] Vision enhancement failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Cleanup

    private func pruneOldClips() {
        let cutoff = Date().addingTimeInterval(-maxHistory)
        let expired = indexedClips.filter { $0.endTime < cutoff }
        for clip in expired {
            try? FileManager.default.removeItem(at: clip.fileURL)
        }
        indexedClips.removeAll { $0.endTime < cutoff }
        clipCount = indexedClips.count
    }

    private func cleanupAllClips() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: clipsDirectory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
