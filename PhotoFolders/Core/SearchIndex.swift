import Foundation

/// Something that knows which words mean nearly the same thing (on the phone: Apple's built-in word embedding).
protocol SemanticMatcher: AnyObject {
    /// Words close in meaning to `word`, closest first.
    func neighbors(of word: String, limit: Int) -> [String]
    /// 0...1 closeness of two words, nil when either word is unknown.
    func closeness(_ a: String, _ b: String) -> Double?
}

struct SearchHit: Identifiable, Hashable {
    let id: String
    let score: Double
    let matched: [String]
    let matchedAll: Bool
}

struct SearchOutcome {
    var hits: [SearchHit] = []
    /// What each typed word was understood as, e.g. ("puppy", ["dog"]).
    var understood: [(term: String, meanings: [String])] = []
    var dateLabel: String?
    var fullMatchCount = 0
    var categoryIDs: [String] = []
    var isEmptyQuery = true
}

/// Instant, typo-tolerant, meaning-aware search over labels, words read in photos, folder names and dates.
final class SearchIndex {
    private let records: [PhotoRecord]
    private let idToIndex: [String: Int]
    private var labelPostings: [String: [(Int, Float)]] = [:]
    private var tokenToLabels: [String: Set<String>] = [:]
    private var labelTokens: [String] = []
    private var textPostings: [String: [Int]] = [:]
    private var textVocab: [String] = []
    private var categoryTokens: [String: [String]] = [:]    // word -> category ids
    private var categoryMembers: [String: [Int]] = [:]
    private let matcher: SemanticMatcher?
    private let lock = NSLock()
    private var labelCache: [String: [String: Double]] = [:]

    var photoCount: Int { records.count }

    init(records: [PhotoRecord], categories: [PhotoCategory], matcher: SemanticMatcher?) {
        self.records = records
        self.matcher = matcher
        var idx: [String: Int] = [:]
        for (i, r) in records.enumerated() { idx[r.id] = i }
        idToIndex = idx

        for (i, r) in records.enumerated() {
            for l in r.labels where l.confidence >= 0.08 { labelPostings[l.name, default: []].append((i, l.confidence)) }
            for t in r.traits { labelPostings[t, default: []].append((i, 1.0)) }
            if !r.text.isEmpty {
                for w in Set(TextTools.words(r.text)) where w.count >= 2 { textPostings[w, default: []].append(i) }
            }
        }
        for label in labelPostings.keys {
            for tok in TextTools.words(label) {
                tokenToLabels[tok, default: []].insert(label)
                tokenToLabels[TextTools.singular(tok), default: []].insert(label)
            }
        }
        labelTokens = tokenToLabels.keys.sorted()
        textVocab = textPostings.keys.sorted()

        for c in categories {
            categoryMembers[c.id] = c.photoIDs.compactMap { idx[$0] }
            let words = Set(TextTools.words(c.name).map(TextTools.singular) + TextTools.words(c.name))
            for w in words where !Vocabulary.stopwords.contains(w) { categoryTokens[w, default: []].append(c.id) }
        }
    }

    // MARK: - Query

    func search(_ raw: String, now: Date = Date(), calendar: Calendar = .current, limit: Int = 3000) -> SearchOutcome {
        let parsed = DateQueryParser(now: now, calendar: calendar).parse(raw)
        let typingLastWord = !(raw.last.map { $0 == " " } ?? true)
        var terms = parsed.remaining.filter { !Vocabulary.stopwords.contains($0) }

        // Two-word labels typed as two words ("christmas tree", "swimming pool").
        var merged: [String] = []
        var i = 0
        while i < terms.count {
            if i + 1 < terms.count {
                let pair = terms[i] + " " + terms[i + 1]
                let pairSingular = terms[i] + " " + TextTools.singular(terms[i + 1])
                if labelPostings[pair] != nil { merged.append(pair); i += 2; continue }
                if labelPostings[pairSingular] != nil { merged.append(pairSingular); i += 2; continue }
            }
            merged.append(terms[i]); i += 1
        }
        terms = merged

        var outcome = SearchOutcome()
        outcome.dateLabel = parsed.label
        outcome.isEmptyQuery = terms.isEmpty && parsed.range == nil
        if outcome.isEmptyQuery { return outcome }

        let inRange: (Int) -> Bool = { idx in
            guard let range = parsed.range else { return true }
            guard let d = self.records[idx].date else { return false }
            return range.contains(d)
        }

        if terms.isEmpty {
            let hits = records.indices.filter(inRange)
                .sorted { (records[$0].date ?? .distantPast) > (records[$1].date ?? .distantPast) }
                .prefix(limit)
                .map { SearchHit(id: records[$0].id, score: 1, matched: [], matchedAll: true) }
            outcome.hits = Array(hits)
            outcome.fullMatchCount = hits.count
            return outcome
        }

        var score: [Int: Double] = [:]
        var matchedCount: [Int: Int] = [:]
        var matchedWhat: [Int: [String]] = [:]
        var categoryHits = Set<String>()

        for (ti, term) in terms.enumerated() {
            let isLast = ti == terms.count - 1 && typingLastWord
            var best: [Int: (Double, String)] = [:]
            func offer(_ idx: Int, _ s: Double, _ why: String) {
                if s > (best[idx]?.0 ?? 0) { best[idx] = (s, why) }
            }

            let labels = labelMatches(term, isLast: isLast)
            let meanings = labels.filter { $0.value >= 0.6 }.sorted { $0.value > $1.value }.prefix(4).map(\.key)
            outcome.understood.append((term: term, meanings: Array(meanings)))
            for (label, w) in labels {
                for (idx, conf) in labelPostings[label] ?? [] { offer(idx, w * Double(conf).squareRoot(), label) }
            }
            for (idx, w) in textMatches(term, isLast: isLast) { offer(idx, w, "“\(term)”") }
            for cid in categoryMatches(term, isLast: isLast) {
                categoryHits.insert(cid)
                for idx in categoryMembers[cid] ?? [] { offer(idx, 0.55, "folder") }
            }

            for (idx, (s, why)) in best where s >= 0.12 && inRange(idx) {
                score[idx, default: 0] += s
                matchedCount[idx, default: 0] += 1
                if !(matchedWhat[idx]?.contains(why) ?? false) { matchedWhat[idx, default: []].append(why) }
            }
        }

        let ranked = score.keys.sorted { a, b in
            let ma = matchedCount[a] ?? 0, mb = matchedCount[b] ?? 0
            if ma != mb { return ma > mb }
            if score[a]! != score[b]! { return score[a]! > score[b]! }
            return (records[a].date ?? .distantPast) > (records[b].date ?? .distantPast)
        }
        outcome.hits = ranked.prefix(limit).map { idx in
            SearchHit(id: records[idx].id, score: score[idx] ?? 0, matched: matchedWhat[idx] ?? [],
                      matchedAll: (matchedCount[idx] ?? 0) == terms.count)
        }
        outcome.fullMatchCount = outcome.hits.filter(\.matchedAll).count
        outcome.categoryIDs = Array(categoryHits).sorted { (categoryMembers[$0]?.count ?? 0) > (categoryMembers[$1]?.count ?? 0) }
        return outcome
    }

    // MARK: - Matching one word

    /// Labels a word can mean, with a 0...1 weight.
    func labelMatches(_ term: String, isLast: Bool) -> [String: Double] {
        let key = term + (isLast ? "|p" : "")
        lock.lock()
        if let cached = labelCache[key] { lock.unlock(); return cached }
        lock.unlock()

        var out: [String: Double] = [:]
        func add(_ label: String, _ w: Double) { if w > (out[label] ?? 0) { out[label] = w } }
        let variants = Set([term, TextTools.singular(term)])

        for v in variants {
            if labelPostings[v] != nil { add(v, 1.0) }
            for l in tokenToLabels[v] ?? [] { add(l, l == v ? 1.0 : 0.88) }
            for target in Vocabulary.synonyms[v] ?? [] {
                if labelPostings[target] != nil { add(target, 0.92) }
                for l in tokenToLabels[target] ?? [] { add(l, 0.82) }
            }
        }
        if isLast, term.count >= 2, !term.contains(" ") {
            for tok in prefixed(labelTokens, term) where tok != term {
                for l in tokenToLabels[tok] ?? [] { add(l, 0.7) }
            }
        }
        if term.count >= 4, !term.contains(" ") {
            let limit = term.count >= 8 ? 2 : 1
            for tok in labelTokens where abs(tok.count - term.count) <= limit && tok != term {
                if TextTools.editDistance(term, tok, limit: limit) <= limit {
                    for l in tokenToLabels[tok] ?? [] { add(l, 0.76) }
                    for target in Vocabulary.synonyms[tok] ?? [] {
                        if labelPostings[target] != nil { add(target, 0.7) }
                    }
                }
            }
            for (syn, targets) in Vocabulary.synonyms where abs(syn.count - term.count) <= limit && syn != term {
                if TextTools.editDistance(term, syn, limit: limit) <= limit {
                    for target in targets where labelPostings[target] != nil { add(target, 0.72) }
                }
            }
        }
        if let m = matcher, (out.values.max() ?? 0) < 0.9, !term.contains(" ") {
            let near = m.neighbors(of: term, limit: 40)
            for (rank, n) in near.enumerated() {
                let word = TextTools.singular(TextTools.fold(n))
                let w = 0.8 - 0.4 * Double(rank) / Double(max(1, near.count))
                for l in tokenToLabels[word] ?? [] { add(l, w) }
                for target in Vocabulary.synonyms[word] ?? [] where labelPostings[target] != nil { add(target, w - 0.05) }
            }
            for tok in labelTokens {
                if let c = m.closeness(term, tok), c >= 0.6 {
                    for l in tokenToLabels[tok] ?? [] { add(l, 0.3 + 0.5 * c) }
                }
            }
        }

        lock.lock(); labelCache[key] = out; lock.unlock()
        return out
    }

    /// Photos whose readable text contains the word.
    private func textMatches(_ term: String, isLast: Bool) -> [Int: Double] {
        var out: [Int: Double] = [:]
        func add(_ ids: [Int], _ w: Double) { for i in ids where w > (out[i] ?? 0) { out[i] = w } }
        let words = term.split(separator: " ").map(String.init)
        if words.count > 1 {
            // Two-word label phrase: require both words in the text.
            var sets = words.map { Set(textPostings[$0] ?? []) }
            let first = sets.removeFirst()
            add(Array(sets.reduce(first) { $0.intersection($1) }), 0.8)
            return out
        }
        add(textPostings[term] ?? [], 0.85)
        let single = TextTools.singular(term)
        if single != term { add(textPostings[single] ?? [], 0.8) }
        if isLast, term.count >= 3 {
            for w in prefixed(textVocab, term).prefix(300) where w != term { add(textPostings[w] ?? [], 0.55) }
        }
        if term.count >= 5, textVocab.count < 120_000 {
            let limit = term.count >= 9 ? 2 : 1
            for w in textVocab where abs(w.count - term.count) <= limit && w != term {
                if TextTools.editDistance(term, w, limit: limit) <= limit { add(textPostings[w] ?? [], 0.5) }
            }
        }
        return out
    }

    private func categoryMatches(_ term: String, isLast: Bool) -> [String] {
        var out = Set(categoryTokens[term] ?? [])
        out.formUnion(categoryTokens[TextTools.singular(term)] ?? [])
        if isLast, term.count >= 3 {
            for (w, ids) in categoryTokens where w.hasPrefix(term) { out.formUnion(ids) }
        }
        return Array(out)
    }

    /// Words in a sorted list that start with `prefix` (binary search).
    private func prefixed(_ sorted: [String], _ prefix: String) -> ArraySlice<String> {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < prefix { lo = mid + 1 } else { hi = mid }
        }
        var end = lo
        while end < sorted.count, sorted[end].hasPrefix(prefix) { end += 1 }
        return sorted[lo..<end]
    }
}
