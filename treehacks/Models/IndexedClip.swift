//
//  IndexedClip.swift
//  treehacks
//
//  Represents a short video clip that has been analyzed and indexed
//  for semantic search. Each clip carries its file URL, time range,
//  descriptive keywords, and an NLEmbedding vector.
//

import Foundation

struct IndexedClip: Identifiable {
    let id = UUID()
    let fileURL: URL
    let startTime: Date
    let endTime: Date
    var keywords: Set<String>
    var description: String
    var embedding: [Double]?

    /// How many seconds ago this clip was recorded (relative to now).
    var secondsAgo: TimeInterval {
        Date().timeIntervalSince(endTime)
    }

    /// Human-readable time label.
    var timeAgoLabel: String {
        let secs = Int(secondsAgo)
        if secs < 5 { return "just now" }
        if secs < 60 { return "\(secs)s ago" }
        let mins = secs / 60
        return "\(mins)m ago"
    }
}
