import Foundation

/// A folder the person made: a name, an optional description ("receipts", "dogs at the beach"),
/// optional example photos, and their own corrections. Re-applied every time photos change.
struct CustomFolder: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var describe: String = ""
    var exampleIDs: [String] = []
    /// 0 = only very close look-alikes of the examples, 1 = loosely similar.
    var closeness: Double = 0.5
    var excluded: [String] = []
    var included: [String] = []
    var created: Date = Date()

    var categoryID: String { "custom." + id }
    var hasRule: Bool {
        !describe.trimmingCharacters(in: .whitespaces).isEmpty || !exampleIDs.isEmpty || !included.isEmpty
    }
}

/// A compact picture of what a photo looks like (Apple's image feature print, squeezed to one byte per number).
struct LookVector: Hashable {
    let values: [Int8]
    let norm: Float

    init(values: [Int8]) {
        self.values = values
        var s: Float = 0
        for v in values { s += Float(v) * Float(v) }
        norm = s.squareRoot()
    }

    init?(data: Data) {
        guard !data.isEmpty else { return nil }
        self.init(values: data.map { Int8(bitPattern: $0) })
    }

    var data: Data { Data(values.map { UInt8(bitPattern: $0) }) }

    /// Squeezes a float vector to one byte per number, keeping its direction.
    static func quantize(_ floats: [Float]) -> LookVector? {
        let maxAbs = floats.reduce(Float(0)) { max($0, abs($1)) }
        guard maxAbs > 0, !floats.isEmpty else { return nil }
        return LookVector(values: floats.map { Int8(max(-127, min(127, ($0 / maxAbs * 127).rounded()))) })
    }

    /// Cosine similarity, -1...1.
    func similarity(_ other: LookVector) -> Float {
        guard values.count == other.values.count, norm > 0, other.norm > 0 else { return 0 }
        var dot: Int32 = 0
        values.withUnsafeBufferPointer { a in
            other.values.withUnsafeBufferPointer { b in
                for i in 0..<a.count { dot &+= Int32(a[i]) * Int32(b[i]) }
            }
        }
        return Float(dot) / (norm * other.norm)
    }
}

enum CustomFolderResolver {
    struct Result {
        /// Every photo the rules pick, before the person's own removals, newest first.
        var candidates: [String]
        /// What actually goes in the folder.
        var members: [String]
    }

    static func resolve(_ folder: CustomFolder, records: [PhotoRecord], search: SearchIndex?,
                        looks: [String: LookVector], now: Date = Date(), calendar: Calendar = .current) -> Result {
        var picked = Set<String>()
        let describe = folder.describe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !describe.isEmpty, let search {
            let outcome = search.search(describe + " ", now: now, calendar: calendar, limit: Int.max)
            for hit in outcome.hits where hit.matchedAll { picked.insert(hit.id) }
        }

        let examples = folder.exampleIDs.compactMap { looks[$0] }
        if !examples.isEmpty {
            let threshold = lookThreshold(examples: examples, all: looks, closeness: folder.closeness)
            for (id, v) in looks {
                var best: Float = -1
                for e in examples { best = max(best, v.similarity(e)) }
                if best >= threshold { picked.insert(id) }
            }
        }
        picked.formUnion(folder.exampleIDs)
        picked.formUnion(folder.included)

        let dates = Dictionary(records.map { ($0.id, $0.date ?? .distantPast) }, uniquingKeysWith: { a, _ in a })
        let known = picked.filter { dates[$0] != nil }
        let candidates = known.sorted { dates[$0]! > dates[$1]! }
        let excluded = Set(folder.excluded)
        return Result(candidates: candidates, members: candidates.filter { !excluded.contains($0) })
    }

    /// How alike a photo must be to an example. With several examples, "as alike as the examples are to each
    /// other"; with one, the closest few percent of the library. The closeness slider moves it either way.
    static func lookThreshold(examples: [LookVector], all: [String: LookVector], closeness: Double) -> Float {
        var base: Float
        if examples.count >= 2 {
            var sims: [Float] = []
            for i in 0..<examples.count {
                var best: Float = -1
                for j in 0..<examples.count where j != i { best = max(best, examples[i].similarity(examples[j])) }
                sims.append(best)
            }
            base = sims.reduce(0, +) / Float(sims.count)
        } else {
            let e = examples[0]
            let sims = all.values.map { e.similarity($0) }.sorted(by: >)
            let k = min(sims.count - 1, max(3, sims.count / 30))
            base = sims.isEmpty ? 0.9 : sims[max(0, k)]
        }
        let shift = Float(0.5 - closeness) * 0.6 * max(0.2, 1 - base)
        return min(0.995, base + shift)
    }
}

extension CategoryEngine {
    /// Everything the home screen shows: the person's own folders first (their photos leave the invented
    /// folders), then the invented ones; plus the search index over all of it.
    static func buildAll(records: [PhotoRecord], looks: [String: LookVector], customFolders: [CustomFolder],
                         options: Options, matcher: SemanticMatcher?, now: Date = Date())
        -> (categories: [PhotoCategory], index: SearchIndex, baseIndex: SearchIndex) {
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let base = SearchIndex(records: records, categories: [], matcher: matcher)
        var claimed = Set<String>()
        var custom: [PhotoCategory] = []
        for f in customFolders.sorted(by: { $0.created < $1.created }) {
            let members = CustomFolderResolver.resolve(f, records: records, search: base, looks: looks, now: now).members
            claimed.formUnion(members)
            let recs = members.compactMap { byID[$0] }
            let words = TextTools.words(f.name + " " + f.describe).map(TextTools.singular)
            let symbol = Vocabulary.symbol(for: words)
            custom.append(PhotoCategory(
                id: f.categoryID, name: f.name, keywords: [], symbol: symbol == "folder.fill" ? "star.fill" : symbol,
                kind: .custom, photoIDs: recs.map(\.id), coverIDs: pickCovers(recs),
                groups: Grouper.groups(categoryID: f.categoryID, records: recs, categoryKeywords: [])))
        }
        let invented = build(records: records.filter { !claimed.contains($0.id) }, options: options)
        let all = custom + invented
        return (all, SearchIndex(records: records, categories: all, matcher: matcher), base)
    }
}
