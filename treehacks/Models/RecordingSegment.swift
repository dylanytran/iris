//
//  RecordingSegment.swift
//  treehacks
//
//  Created by Dylan Tran on 2/14/26.
//

import Foundation

struct RecordingSegment: Identifiable {
    let id = UUID()
    let fileURL: URL
    let startTime: Date
    var endTime: Date?

    var duration: TimeInterval {
        guard let end = endTime else {
            return Date().timeIntervalSince(startTime)
        }
        return end.timeIntervalSince(startTime)
    }
}
