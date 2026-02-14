//
//  MeetingTranscript.swift
//  treehacks
//
//  Model for storing transcripts from Zoom calls.
//  Captures instructions given during video calls for later reference.
//

import Foundation
import SwiftData

@Model
final class MeetingTranscript {
    /// Unique identifier
    var id: UUID
    
    /// Title of the meeting (e.g., "Doctor Appointment", "Caregiver Check-in")
    var title: String
    
    /// The full transcript text
    var transcript: String
    
    /// Key instructions extracted from the transcript (can be edited by user)
    var instructions: String
    
    /// When the call took place
    var date: Date
    
    /// Duration of the call in seconds
    var duration: TimeInterval
    
    /// Participant names if known
    var participants: [String]
    
    /// Optional tags for categorization
    var tags: [String]
    
    init(
        id: UUID = UUID(),
        title: String,
        transcript: String = "",
        instructions: String = "",
        date: Date = Date(),
        duration: TimeInterval = 0,
        participants: [String] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.transcript = transcript
        self.instructions = instructions
        self.date = date
        self.duration = duration
        self.participants = participants
        self.tags = tags
    }
}

// MARK: - Convenience Extensions

extension MeetingTranscript {
    /// Formatted date string
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// Formatted duration string (e.g., "15:30")
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Preview of transcript (first 100 chars)
    var transcriptPreview: String {
        if transcript.count > 100 {
            return String(transcript.prefix(100)) + "..."
        }
        return transcript
    }
}
