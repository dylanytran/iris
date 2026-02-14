//
//  RecordingManager.swift
//  treehacks
//
//  Created by Dylan Tran on 2/14/26.
//

import AVFoundation
import Combine
import Foundation

/// Manages rolling video recording in 30-second segments.
/// Keeps the last N segments (configurable, default 5 minutes worth).
/// Provides time-based retrieval for memory recall playback.
class RecordingManager: NSObject, ObservableObject {

    // MARK: - Configuration

    /// Duration of each recording segment in seconds
    let segmentDuration: TimeInterval = 30

    /// Maximum total duration of recordings to keep (seconds)
    let maxTotalDuration: TimeInterval = 300 // 5 minutes

    // MARK: - Published State

    @Published var isRecording = false
    @Published var segments: [RecordingSegment] = []
    @Published var oldestAvailableDate: Date?
    @Published var totalRecordedDuration: TimeInterval = 0

    // MARK: - Private

    private weak var cameraManager: CameraManager?
    private var currentSegment: RecordingSegment?
    private var segmentTimer: Timer?
    private let recordingsDirectory: URL

    // MARK: - Init

    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager

        // Create recordings directory
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.recordingsDirectory = docs.appendingPathComponent("recordings", isDirectory: true)

        super.init()

        // Create directory if needed
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        // Set ourselves as the recording delegate
        cameraManager.recordingDelegate = self

        // Clean up old recordings from previous sessions
        cleanupOldFiles()
    }

    // MARK: - Recording Control

    func startRollingRecording() {
        guard !isRecording else { return }
        isRecording = true
        startNewSegment()
        scheduleSegmentRotation()
    }

    func stopRollingRecording() {
        isRecording = false
        segmentTimer?.invalidate()
        segmentTimer = nil
        cameraManager?.stopRecording()
    }

    // MARK: - Segment Management

    private func startNewSegment() {
        let timestamp = Date()
        let fileName = "segment_\(Int(timestamp.timeIntervalSince1970)).mov"
        let fileURL = recordingsDirectory.appendingPathComponent(fileName)

        currentSegment = RecordingSegment(fileURL: fileURL, startTime: timestamp)
        cameraManager?.startRecording(to: fileURL)
    }

    private func scheduleSegmentRotation() {
        segmentTimer?.invalidate()
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] _ in
            self?.rotateSegment()
        }
    }

    private func rotateSegment() {
        // Stop current recording (will trigger delegate callback)
        cameraManager?.stopRecording()

        // Start new segment after a brief delay to allow file finalization
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.isRecording else { return }
            self.startNewSegment()
        }
    }

    // MARK: - Retrieval

    /// Find the recording segment and time offset for a given past time.
    /// - Parameter secondsAgo: How many seconds in the past to look.
    /// - Returns: Tuple of (file URL, seek time offset within that file), or nil if not available.
    func getRecording(secondsAgo: TimeInterval) -> (url: URL, seekTime: TimeInterval)? {
        let targetDate = Date().addingTimeInterval(-secondsAgo)
        return getRecording(at: targetDate)
    }

    func getRecording(at date: Date) -> (url: URL, seekTime: TimeInterval)? {
        // Find the segment that contains this date
        for segment in segments {
            let endTime = segment.endTime ?? Date()
            if date >= segment.startTime && date <= endTime {
                let seekTime = date.timeIntervalSince(segment.startTime)
                // Verify file exists
                if FileManager.default.fileExists(atPath: segment.fileURL.path) {
                    return (segment.fileURL, seekTime)
                }
            }
        }
        return nil
    }

    /// Get all segment URLs in chronological order for continuous playback from a given time.
    func getRecordings(from secondsAgo: TimeInterval) -> [(url: URL, seekTime: TimeInterval)] {
        let targetDate = Date().addingTimeInterval(-secondsAgo)
        var results: [(url: URL, seekTime: TimeInterval)] = []

        let sortedSegments = segments.sorted { $0.startTime < $1.startTime }

        for segment in sortedSegments {
            let endTime = segment.endTime ?? Date()
            guard FileManager.default.fileExists(atPath: segment.fileURL.path) else { continue }

            if segment.startTime <= targetDate && targetDate <= endTime {
                // This is the first segment - seek into it
                let seekTime = targetDate.timeIntervalSince(segment.startTime)
                results.append((segment.fileURL, seekTime))
            } else if segment.startTime > targetDate {
                // Subsequent segments - play from beginning
                results.append((segment.fileURL, 0))
            }
        }

        return results
    }

    /// Maximum seconds we can go back
    var maxRecallSeconds: TimeInterval {
        guard let oldest = segments.first?.startTime else { return 0 }
        return Date().timeIntervalSince(oldest)
    }

    // MARK: - Cleanup

    private func pruneOldSegments() {
        let cutoff = Date().addingTimeInterval(-maxTotalDuration)
        let old = segments.filter { $0.startTime < cutoff }

        for segment in old {
            try? FileManager.default.removeItem(at: segment.fileURL)
        }

        segments.removeAll { $0.startTime < cutoff }
        updateMetadata()
    }

    private func cleanupOldFiles() {
        // Remove any leftover recording files from previous sessions
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func updateMetadata() {
        oldestAvailableDate = segments.first?.startTime
        totalRecordedDuration = segments.reduce(0) { $0 + $1.duration }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension RecordingManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        DispatchQueue.main.async {
            // Segment recording started
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let error = error {
                print("Recording error: \(error.localizedDescription)")
                return
            }

            // Finalize the current segment
            if var segment = self.currentSegment, segment.fileURL == outputFileURL {
                segment.endTime = Date()
                self.segments.append(segment)
                self.currentSegment = nil
            }

            // Prune old segments
            self.pruneOldSegments()
        }
    }
}
