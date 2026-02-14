//
//  OpenAIClient.swift
//  treehacks
//
//  Calls OpenAI Chat Completions to turn (memory/context, question) into a natural answer.
//  API key is read from Secrets.plist (gitignored). Copy Secrets.plist.example to Secrets.plist and add your key.
//  Adapted from TreeHacksTest.
//

import Foundation

struct OpenAIClient {

    private static let url = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let model = "gpt-4o-mini"
    private static let promptTemplate = """
    Context from what the user recently saw: "%@"
    Question: %@
    Answer in one short sentence based only on the context. Do not repeat the context verbatim.
    """

    /// Reads OpenAI API key from Secrets.plist in the app bundle. Returns nil if missing.
    static func loadAPIKey() -> String? {
        guard let plistURL = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let key = plist["OpenAIAPIKey"] as? String,
              !key.isEmpty else { return nil }
        return key
    }

    /// Sends (context, question) to OpenAI and returns the generated answer, or nil on failure.
    static func generateAnswer(memory: String, question: String) async throws -> String? {
        guard let apiKey = loadAPIKey() else { return nil }
        let prompt = String(format: promptTemplate, memory, question)

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
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
