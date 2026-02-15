//
//  AppSpeechManager.swift
//  treehacks
//
//  Shared TTS for memory recall descriptions, Zoom announcements, call announcements, and error messages.
//

import AVFoundation

final class AppSpeechManager {

    static let shared = AppSpeechManager()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    /// Speak the given text. Uses system default voice.
    func speak(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let u = AVSpeechUtterance(string: t)
            u.voice = nil
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
            self.synthesizer.speak(u)
        }
    }

    /// Stop current and queued speech.
    func stop() {
        DispatchQueue.main.async { [weak self] in
            self?.synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
