//
//  ClipSearchEngine.swift
//  treehacks
//
//  Uses Apple's Natural Language sentence embedding model to perform
//  semantic search over indexed video clip descriptions.
//  All NLEmbedding access is confined to a single serial queue to avoid
//  EXC_BAD_ACCESS (NLEmbedding is not thread-safe).
//  Falls back to keyword matching when embeddings are unavailable.
//

import Foundation
import NaturalLanguage

/// Result of a clip search, including debug info.
struct ClipSearchResult {
    let clip: IndexedClip
    let score: Double
    let method: String  // "embedding", "keyword", or "recent"
}

/// Max character count for embedding input to avoid edge-case crashes.
private let maxEmbeddingInputLength = 10_000

final class ClipSearchEngine {

    private let embedding: NLEmbedding?
    /// Serial queue for all NLEmbedding usage (not thread-safe).
    private let nlQueue = DispatchQueue(label: "com.treehacks.clipSearchEngine.nl", qos: .userInitiated)

    init() {
        // Create embedding on the queue that will use it so we never touch it from another thread.
        embedding = nlQueue.sync { NLEmbedding.sentenceEmbedding(for: .english) }
    }

    var isAvailable: Bool { embedding != nil }

    // MARK: - Embedding

    /// Compute embedding vector for a text description. Safe to call from any thread.
    func computeEmbedding(for text: String) -> [Double]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxEmbeddingInputLength else { return nil }
        return nlQueue.sync {
            guard let embedding = embedding else { return nil }
            return embedding.vector(for: trimmed)
        }
    }

    // MARK: - Primary Search (Embedding)

    /// Find the best matching indexed clip using embedding similarity.
    func findBestClipByEmbedding(for query: String, in clips: [IndexedClip]) -> ClipSearchResult? {
        guard !clips.isEmpty else { return nil }
        let queryVector: [Double]? = nlQueue.sync {
            guard let embedding = embedding else { return nil }
            let t = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t.count <= maxEmbeddingInputLength else { return nil }
            return embedding.vector(for: t)
        }
        guard let queryVector = queryVector else { return nil }

        var bestClip: IndexedClip?
        var bestScore: Double = -1.0

        for clip in clips {
            guard let clipVector = clip.embedding else { continue }
            let score = Self.cosineSimilarity(queryVector, clipVector)
            if score > bestScore {
                bestScore = score
                bestClip = clip
            }
        }

        guard let clip = bestClip else { return nil }
        return ClipSearchResult(clip: clip, score: bestScore, method: "embedding")
    }

    // MARK: - Fallback Search (Keyword)

    /// Find the best matching clip by counting keyword overlaps with the query.
    func findBestClipByKeyword(for query: String, in clips: [IndexedClip]) -> ClipSearchResult? {
        guard !clips.isEmpty else { return nil }

        let queryWords = Set(
            query.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .flatMap { $0.components(separatedBy: .punctuationCharacters) }
                .filter { $0.count > 2 }  // Skip tiny words
        )

        guard !queryWords.isEmpty else { return nil }

        var bestClip: IndexedClip?
        var bestScore: Double = 0

        for clip in clips {
            let clipWords = Set(
                clip.keywords
                    .flatMap { $0.lowercased().components(separatedBy: .whitespacesAndNewlines) }
                    .flatMap { $0.components(separatedBy: .punctuationCharacters) }
                    .filter { $0.count > 2 }
            )

            // Also include description words
            let descWords = Set(
                clip.description.lowercased()
                    .components(separatedBy: .whitespacesAndNewlines)
                    .flatMap { $0.components(separatedBy: .punctuationCharacters) }
                    .filter { $0.count > 2 }
            )

            let allClipWords = clipWords.union(descWords)
            let overlap = queryWords.intersection(allClipWords)
            let score = Double(overlap.count) / Double(queryWords.count)

            if score > bestScore {
                bestScore = score
                bestClip = clip
            }
        }

        guard let clip = bestClip, bestScore > 0 else { return nil }
        return ClipSearchResult(clip: clip, score: bestScore, method: "keyword")
    }

    // MARK: - Combined Search (with fallbacks)

    /// Search using embedding first, then keyword fallback, then most recent clip.
    /// Always returns a result if there are any clips available.
    func findBestClip(for query: String, in clips: [IndexedClip]) -> ClipSearchResult? {
        guard !clips.isEmpty else { return nil }

        // Try embedding search first
        if let result = findBestClipByEmbedding(for: query, in: clips) {
            return result
        }

        // Fallback to keyword matching
        if let result = findBestClipByKeyword(for: query, in: clips) {
            return result
        }

        // Last resort: return the most recent clip
        if let mostRecent = clips.max(by: { $0.endTime < $1.endTime }) {
            return ClipSearchResult(clip: mostRecent, score: 0, method: "recent")
        }

        return nil
    }

    // MARK: - Debug: Score all clips

    /// Score every clip against a query for debug display.
    func scoreAllClips(for query: String, in clips: [IndexedClip]) -> [(clip: IndexedClip, score: Double)] {
        let queryVector: [Double]? = nlQueue.sync {
            guard let embedding = embedding else { return nil }
            let t = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t.count <= maxEmbeddingInputLength else { return nil }
            return embedding.vector(for: t)
        }
        guard let queryVector = queryVector else {
            return clips.map { ($0, 0.0) }
        }

        return clips.map { clip in
            guard let clipVector = clip.embedding else { return (clip, 0.0) }
            let score = Self.cosineSimilarity(queryVector, clipVector)
            return (clip, score)
        }
        .sorted { $0.score > $1.score }
    }

    // MARK: - Math

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        var dot: Double = 0, normA: Double = 0, normB: Double = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}
