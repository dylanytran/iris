//
//  SpeechRecognizer.swift
//  treehacks
//
//  Wraps Apple's Speech framework to convert voice input to text.
//  Used for voice-based memory queries.
//

import Speech
import AVFoundation

final class SpeechRecognizer: ObservableObject {

    // MARK: - Published State

    @Published var transcript = ""
    @Published var isListening = false
    @Published var isAvailable = false
    @Published var errorMessage: String?

    // MARK: - Callback

    /// Called on the main thread after listening finishes (whether by user, timeout, or error).
    /// The String parameter is the final transcript (may be empty).
    var onFinished: ((String) -> Void)?

    // MARK: - Private

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasTapInstalled = false

    init() {
        isAvailable = speechRecognizer?.isAvailable ?? false
    }

    // MARK: - Permissions

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.isAvailable = true
                    self?.errorMessage = nil
                    print("[SpeechRecognizer] Authorization granted")
                case .denied:
                    self?.isAvailable = false
                    self?.errorMessage = "Speech recognition permission denied."
                    print("[SpeechRecognizer] Authorization denied")
                case .restricted:
                    self?.isAvailable = false
                    self?.errorMessage = "Speech recognition is restricted on this device."
                    print("[SpeechRecognizer] Authorization restricted")
                case .notDetermined:
                    self?.isAvailable = false
                    print("[SpeechRecognizer] Authorization not determined")
                @unknown default:
                    self?.isAvailable = false
                }
            }
        }
    }

    // MARK: - Listening

    func startListening() {
        print("[SpeechRecognizer] startListening called, isListening=\(isListening)")
        guard !isListening else {
            print("[SpeechRecognizer] Already listening, skipping")
            return
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Always clean up any leftover audio tap first
        cleanupAudioTap()

        // Configure audio session for recording
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("[SpeechRecognizer] Audio session configured for recording")
        } catch {
            let msg = "Audio session error: \(error.localizedDescription)"
            errorMessage = msg
            print("[SpeechRecognizer] \(msg)")
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            errorMessage = "Could not create speech recognition request."
            print("[SpeechRecognizer] Failed to create recognition request")
            return
        }
        request.shouldReportPartialResults = true

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer is not available."
            print("[SpeechRecognizer] Recognizer unavailable")
            return
        }

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            var finished = false

            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcript = text
                }
                finished = result.isFinal
                if finished {
                    print("[SpeechRecognizer] Got final result: \"\(text)\"")
                }
            }

            if error != nil {
                print("[SpeechRecognizer] Recognition error: \(error!.localizedDescription)")
                finished = true
            }

            if finished {
                DispatchQueue.main.async {
                    self.finishListening()
                }
            }
        }

        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("[SpeechRecognizer] Recording format: \(recordingFormat)")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        hasTapInstalled = true

        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            // Set state SYNCHRONOUSLY since we're on the main thread
            self.transcript = ""
            self.isListening = true
            self.errorMessage = nil
            print("[SpeechRecognizer] Audio engine started, now listening")
        } catch {
            let msg = "Audio engine failed to start: \(error.localizedDescription)"
            errorMessage = msg
            print("[SpeechRecognizer] \(msg)")
            // Clean up the tap we just installed since the engine didn't start
            cleanupAudioTap()
        }
    }

    /// Called when speech recognition finishes (final result, error, or user-initiated stop).
    /// Always runs on the main thread.
    private func finishListening() {
        guard isListening else {
            print("[SpeechRecognizer] finishListening called but already not listening")
            return
        }

        print("[SpeechRecognizer] finishListening, transcript=\"\(transcript)\"")

        // Stop the audio engine and clean up
        audioEngine.stop()
        cleanupAudioTap()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        // Set state SYNCHRONOUSLY (we're already on main thread)
        isListening = false

        // Restore audio session
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? audioSession.setActive(true)

        // Notify via callback
        let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[SpeechRecognizer] Calling onFinished with transcript: \"\(finalTranscript)\"")
        onFinished?(finalTranscript)
    }

    /// User-initiated stop (tapping the button again).
    func stopListening() {
        print("[SpeechRecognizer] stopListening called, isListening=\(isListening)")
        finishListening()
    }

    // MARK: - Cleanup

    private func cleanupAudioTap() {
        if hasTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
    }
}
