import Foundation

// MARK: - API Models

struct TranscriptUpload: Codable {
    let deviceId: String
    let sessionName: String
    let transcript: String
    let durationSeconds: Int
    let participants: [String]
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case sessionName = "session_name"
        case transcript
        case durationSeconds = "duration_seconds"
        case participants
    }
}

struct TranscriptResponse: Codable, Identifiable {
    let id: String
    let deviceId: String
    let sessionName: String
    let transcript: String
    let durationSeconds: Int
    let participants: [String]
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case sessionName = "session_name"
        case transcript
        case durationSeconds = "duration_seconds"
        case participants
        case createdAt = "created_at"
    }
}

struct CognitiveAnalysis: Codable {
    let clarity: Int
    let coherence: Int
    let wordFinding: Int
    let repetition: Int
    let engagement: Int
    let memoryReferences: [String]
    let moodIndicators: [String]
    let concernAreas: [String]
    let strengths: [String]
    let recommendations: [String]
    let overallAssessment: String
    let alertLevel: String // "normal", "mild", "moderate", "significant"
    
    enum CodingKeys: String, CodingKey {
        case clarity, coherence, repetition, engagement
        case wordFinding = "word_finding"
        case memoryReferences = "memory_references"
        case moodIndicators = "mood_indicators"
        case concernAreas = "concern_areas"
        case strengths, recommendations
        case overallAssessment = "overall_assessment"
        case alertLevel = "alert_level"
    }
}

struct ExtractedTask: Codable, Identifiable {
    var id: String { task }
    let task: String
    let type: String // "action", "appointment", "medication", "reminder"
    let priority: String // "high", "medium", "low"
    let dueDate: String?
    let context: String
    
    enum CodingKeys: String, CodingKey {
        case task, type, priority, context
        case dueDate = "due_date"
    }
}

struct TranscriptSummary: Codable {
    let summary: String
    let keyTopics: [String]
    let decisions: [String]
    let followUps: [String]
    let emotionalTone: String
    
    enum CodingKeys: String, CodingKey {
        case summary
        case keyTopics = "key_topics"
        case decisions
        case followUps = "follow_ups"
        case emotionalTone = "emotional_tone"
    }
}

struct TrendAnalysis: Codable {
    let periodAnalyzed: String
    let conversationCount: Int
    let overallTrend: String // "improving", "stable", "declining", "insufficient_data"
    let cognitivePatterns: [String: String]
    let moodPatterns: [String]
    let areasOfConcern: [String]
    let areasOfStrength: [String]
    let recommendations: [String]
    
    enum CodingKeys: String, CodingKey {
        case conversationCount = "conversation_count"
        case periodAnalyzed = "period_analyzed"
        case overallTrend = "overall_trend"
        case cognitivePatterns = "cognitive_patterns"
        case moodPatterns = "mood_patterns"
        case areasOfConcern = "areas_of_concern"
        case areasOfStrength = "areas_of_strength"
        case recommendations
    }
}

struct TranscriptStats: Codable {
    let totalTranscripts: Int
    let totalDuration: Int
    let averageDuration: Double
    let analysisCount: Int
    let taskCount: Int
    
    enum CodingKeys: String, CodingKey {
        case totalTranscripts = "total_transcripts"
        case totalDuration = "total_duration"
        case averageDuration = "average_duration"
        case analysisCount = "analysis_count"
        case taskCount = "task_count"
    }
}

// MARK: - API Service

@MainActor
class TranscriptAPIService: ObservableObject {
    static let shared = TranscriptAPIService()
    
    // TODO: Update this to your Render URL after deployment
    private let baseURL = "https://iris-backend.onrender.com/api"
    
    @Published var transcripts: [TranscriptResponse] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: "device_id") {
            return id
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "device_id")
        return newId
    }
    
    // MARK: - Transcript Operations
    
    func saveTranscript(
        sessionName: String,
        transcript: String,
        durationSeconds: Int,
        participants: [String]
    ) async throws -> TranscriptResponse {
        let upload = TranscriptUpload(
            deviceId: deviceId,
            sessionName: sessionName,
            transcript: transcript,
            durationSeconds: durationSeconds,
            participants: participants
        )
        
        return try await post(endpoint: "/transcripts", body: upload)
    }
    
    func fetchTranscripts() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let response: [TranscriptResponse] = try await get(
            endpoint: "/transcripts?device_id=\(deviceId)"
        )
        transcripts = response
    }
    
    func getTranscript(id: String) async throws -> TranscriptResponse {
        return try await get(endpoint: "/transcripts/\(id)?device_id=\(deviceId)")
    }
    
    func searchTranscripts(query: String) async throws -> [TranscriptResponse] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await get(endpoint: "/transcripts/search?device_id=\(deviceId)&q=\(encoded)")
    }
    
    func deleteTranscript(id: String) async throws {
        try await delete(endpoint: "/transcripts/\(id)?device_id=\(deviceId)")
        transcripts.removeAll { $0.id == id }
    }
    
    // MARK: - Analysis Operations
    
    func analyzeConversation(transcriptId: String) async throws -> CognitiveAnalysis {
        struct Request: Codable {
            let device_id: String
        }
        let response: [String: CognitiveAnalysis] = try await post(
            endpoint: "/analysis/\(transcriptId)/conversation",
            body: Request(device_id: deviceId)
        )
        guard let analysis = response["analysis"] else {
            throw APIError.invalidResponse
        }
        return analysis
    }
    
    func extractTasks(transcriptId: String) async throws -> [ExtractedTask] {
        struct Request: Codable {
            let device_id: String
        }
        struct Response: Codable {
            let tasks: [ExtractedTask]
        }
        let response: Response = try await post(
            endpoint: "/analysis/\(transcriptId)/tasks",
            body: Request(device_id: deviceId)
        )
        return response.tasks
    }
    
    func getSummary(transcriptId: String) async throws -> TranscriptSummary {
        struct Request: Codable {
            let device_id: String
        }
        struct Response: Codable {
            let summary: TranscriptSummary
        }
        let response: Response = try await post(
            endpoint: "/analysis/\(transcriptId)/summary",
            body: Request(device_id: deviceId)
        )
        return response.summary
    }
    
    func getTrends(days: Int = 30) async throws -> TrendAnalysis {
        struct Response: Codable {
            let trends: TrendAnalysis
        }
        let response: Response = try await get(
            endpoint: "/analysis/trends?device_id=\(deviceId)&days=\(days)"
        )
        return response.trends
    }
    
    func getStats() async throws -> TranscriptStats {
        return try await get(endpoint: "/analysis/stats?device_id=\(deviceId)")
    }
    
    // MARK: - HTTP Helpers
    
    private func get<T: Decodable>(endpoint: String) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            throw APIError.notFound
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
    
    private func post<T: Decodable, B: Encodable>(endpoint: String, body: B) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
    
    private func delete(endpoint: String) async throws {
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notFound
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .notFound:
            return "Resource not found"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}
