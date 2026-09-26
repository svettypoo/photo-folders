import Foundation
import NaturalLanguage

/// Apple's built-in English word embedding. Ships inside iOS: no download, no network.
final class NLSemanticMatcher: SemanticMatcher {
    private let embedding: NLEmbedding?
    private let lock = NSLock()
    private var neighborCache: [String: [String]] = [:]

    init() {
        embedding = NLEmbedding.wordEmbedding(for: .english)
    }

    var isAvailable: Bool { embedding != nil }

    func neighbors(of word: String, limit: Int) -> [String] {
        lock.lock(); defer { lock.unlock() }
        if let cached = neighborCache[word] { return cached }
        guard let embedding, embedding.contains(word) else { neighborCache[word] = []; return [] }
        let result = embedding.neighbors(for: word, maximumCount: limit).map(\.0)
        neighborCache[word] = result
        return result
    }

    func closeness(_ a: String, _ b: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        guard let embedding, embedding.contains(a), embedding.contains(b) else { return nil }
        // Cosine distance runs 0 (same) ... 2 (opposite).
        return max(0, 1 - embedding.distance(between: a, and: b))
    }
}
