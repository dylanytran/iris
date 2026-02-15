//
//  OpenAIClient.swift
//  treehacks
//
//  Calls OpenAI Chat Completions for:
//  1. Generating natural-language answers from (memory, question).
//  2. Describing images (vision) to produce accurate search keywords for clips.
//  API key is read from Secrets.plist (gitignored). Copy Secrets.plist.example to Secrets.plist and add your key.
//  Adapted from TreeHacksTest.
//

import Foundation

struct OpenAIClient {

    private static let url = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let model = "gpt-4o-mini"
    private static let answerPromptTemplate = """
    Context from what the user recently saw: "%@"
    Question: %@
    Answer in one short sentence based only on the context. Do not repeat the context verbatim.
    """

    /// Prompt for vision-based keyword extraction. Asks for concrete, searchable terms.
    private static let visionKeywordPromptSingle = """
    You are a keyword tagger for a memory recall app that helps people remember where they placed objects.
    Look at this image and list 5-15 comma-separated keywords describing:
    - Every specific OBJECT you can identify (e.g. keys, phone, wallet, mug, laptop, book)
    - The COLOR of the object (e.g. red, blue, green, yellow, white, black)
    - The LOCATION or setting (e.g. kitchen table, desk, couch, counter, shelf)
    - Any visible TEXT (brand names, labels, signs)
    - Any PEOPLE or ACTIONS (e.g. person sitting, hand holding cup)
    Return ONLY the comma-separated keywords, nothing else. Be specific and concrete.
    """

    /// Prompt for multi-image keyword extraction (3 frames from the same clip).
    private static let visionKeywordPromptMulti = """
    You are a keyword tagger for a memory recall app that helps people remember where they placed objects.
    These images are 3 frames from the same 5-second video clip (beginning, middle, end).
    Look at ALL the images together and list 10-25 comma-separated keywords describing:
    - Every specific OBJECT you can identify across all frames (e.g. keys, phone, wallet, mug, laptop, book)
    - The COLOR of the object (e.g. red, blue, green, yellow, white, black)
    - The LOCATION or setting (e.g. kitchen table, desk, couch, counter, shelf)
    - Any visible TEXT (brand names, labels, signs)
    - Any PEOPLE or ACTIONS (e.g. person sitting, hand holding cup)
    - Any CHANGES between frames (e.g. hand moved, object picked up)
    Return ONLY the comma-separated keywords, nothing else. Be specific and concrete.
    """

    // MARK: - API Key

    /// Reads OpenAI API key from Secrets.plist in the app bundle. Returns nil if missing.
    static func loadAPIKey() -> String? {
        guard let plistURL = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let key = plist["OpenAIAPIKey"] as? String,
              !key.isEmpty else { return nil }
        return key
    }

    /// Whether an API key is configured.
    static var hasAPIKey: Bool { loadAPIKey() != nil }

    // MARK: - Answer Generation

    /// Sends (context, question) to OpenAI and returns the generated answer, or nil on failure.
    static func generateAnswer(memory: String, question: String) async throws -> String? {
        guard let apiKey = loadAPIKey() else { return nil }
        let prompt = String(format: answerPromptTemplate, memory, question)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 80
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]],
            first = choices?.first,
            message = first?["message"] as? [String: Any],
            content = message?["content"] as? String
        return content?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    // MARK: - Vision: Image Description / Keywords

    /// Sends one or more JPEG images to GPT-4o-mini vision and returns comma-separated keywords.
    /// When multiple images are provided they are sent in a single API call (cheaper than separate calls).
    /// Returns nil if no API key is configured or the request fails.
    static func describeImages(_ jpegImages: [Data]) async throws -> [String]? {
        guard !jpegImages.isEmpty else { return nil }
        guard let apiKey = loadAPIKey() else {
            print("[OpenAIClient] No API key, skipping vision")
            return nil
        }

        // Choose the appropriate prompt based on image count
        let prompt = jpegImages.count > 1 ? visionKeywordPromptMulti : visionKeywordPromptSingle

        // Build the multimodal content array: text prompt + all images
        var userContent: [[String: Any]] = [
            ["type": "text", "text": prompt]
        ]
        for jpegData in jpegImages {
            let base64Image = jpegData.base64EncodedString()
            userContent.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64Image)",
                    "detail": "low"  // Use low detail to minimize tokens/cost
                ]
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20  // Slightly longer for multiple images

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": userContent]
            ],
            "max_tokens": 200  // More tokens for richer keywords from 3 images
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[OpenAIClient] Sending vision request with \(jpegImages.count) image(s)...")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("[OpenAIClient] Vision: no HTTP response")
            return nil
        }

        guard (200...299).contains(http.statusCode) else {
            if let errorBody = String(data: data, encoding: .utf8) {
                print("[OpenAIClient] Vision error \(http.statusCode): \(errorBody)")
            }
            return nil
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            print("[OpenAIClient] Vision: could not parse response")
            return nil
        }

        // Parse comma-separated keywords from the response
        let keywords = content
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.count > 1 }

        print("[OpenAIClient] Vision keywords (\(keywords.count)): \(keywords)")
        return keywords.isEmpty ? nil : keywords
    }

    /// Convenience: send a single image.
    static func describeImage(_ jpegData: Data) async throws -> [String]? {
        try await describeImages([jpegData])
    }

    // MARK: - Task Extraction from Transcript

    /// Prompt for extracting tasks/reminders from a call transcript
    private static let taskExtractionPrompt = """
    You are analyzing a transcript from a video call. Extract any actionable tasks, reminders, or to-do items mentioned during the conversation.

    Look for phrases like:
    - "Don't forget to..."
    - "Make sure to..."
    - "Remember to..."
    - "You should..."
    - "Please..."
    - "Can you...?"
    - Any specific action items or commitments made

    Return ONLY a JSON array of task objects. Each task should have:
    - "title": A short, action-oriented title (max 50 chars)
    - "description": Additional context from the conversation (optional)

    If no tasks are found, return an empty array: []

    Example output:
    [
      {"title": "Take medication", "description": "Mentioned as a daily reminder"},
      {"title": "Walk the dogs", "description": "Should be done this evening"}
    ]

    Return ONLY valid JSON, no other text.
    """

    /// Extracts actionable tasks from a call transcript.
    /// Returns an array of (title, description) tuples, or empty if none found or on error.
    static func extractTasksFromTranscript(_ transcript: String) async throws -> [(title: String, description: String)] {
        guard !transcript.isEmpty else { return [] }
        guard let apiKey = loadAPIKey() else {
            print("[OpenAIClient] No API key, skipping task extraction")
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": taskExtractionPrompt],
                ["role": "user", "content": "Transcript:\n\n\(transcript)"]
            ],
            "max_tokens": 500
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[OpenAIClient] Extracting tasks from transcript (\(transcript.count) chars)...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let errorBody = String(data: data, encoding: .utf8) {
                print("[OpenAIClient] Task extraction error: \(errorBody)")
            }
            return []
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            print("[OpenAIClient] Task extraction: could not parse response")
            return []
        }

        print("[OpenAIClient] Task extraction response: \(content)")

        // Parse the JSON array of tasks
        guard let jsonData = content.data(using: .utf8),
              let tasksArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            print("[OpenAIClient] Task extraction: could not parse JSON array")
            return []
        }

        let tasks = tasksArray.compactMap { dict -> (title: String, description: String)? in
            guard let title = dict["title"] as? String, !title.isEmpty else { return nil }
            let description = dict["description"] as? String ?? ""
            return (title: title, description: description)
        }

        print("[OpenAIClient] Extracted \(tasks.count) task(s)")
        return tasks
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
