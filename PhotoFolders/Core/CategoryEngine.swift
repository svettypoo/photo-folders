import Foundation

/// Invents folders from what the on-device model saw: photos whose labels look alike are clustered
/// (spherical k-means over confidence x rarity), and each cluster is named after the labels that
/// set it apart from the rest of the library.
enum CategoryEngine {
    struct Options {
        /// 0.6 = fewer, broader folders; 1 = balanced; 1.6 = more, narrower folders.
        var granularity: Double = 1.0
        var customNames: [String: String] = [:]
    }

    static let screenshotsID = "cat.screenshots"
    static let unsortedID = "cat.unsorted"

    static func build(records: [PhotoRecord], options: Options = Options()) -> [PhotoCategory] {
        let sorted = records.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        var screenshots: [PhotoRecord] = []
        var unsorted: [PhotoRecord] = []
        var pool: [PhotoRecord] = []
        var poolFeatures: [[(String, Float)]] = []
        for r in sorted {
            if r.isScreenshot { screenshots.append(r); continue }
            let f = features(of: r)
            if f.isEmpty { unsorted.append(r) } else { pool.append(r); poolFeatures.append(f) }
        }

        var result: [PhotoCategory] = []
        if !pool.isEmpty {
            result = invent(pool: pool, features: poolFeatures, options: options)
        }
        if !screenshots.isEmpty {
            result.append(special(id: screenshotsID, name: "Screenshots", symbol: "iphone", kind: .screenshots,
                                  records: screenshots, options: options))
        }
        if !unsorted.isEmpty {
            result.append(special(id: unsortedID, name: "Unsorted", symbol: "questionmark.folder.fill", kind: .unsorted,
                                  records: unsorted, options: options))
        }
        return result
    }

    /// The labels used to compare photos: confident, not vague, plus "people" when faces were found.
    static func features(of r: PhotoRecord) -> [(String, Float)] {
        var out: [(String, Float)] = []
        var seen = Set<String>()
        for l in r.labels where l.confidence >= 0.15 && !Vocabulary.genericLabels.contains(l.name) {
            if seen.insert(l.name).inserted { out.append((l.name, l.confidence)) }
            if out.count >= 12 { break }
        }
        if r.faceCount > 0, !seen.contains(Trait.people) { out.append((Trait.people, 0.7)) }
        return out
    }

    static func targetK(_ n: Int, granularity: Double) -> Int {
        guard n > 0 else { return 0 }
        if n < 6 { return 1 }
        let base = 3.0 + 4.0 * log2(max(1.0, Double(n) / 20.0))
        let k = Int((base * granularity).rounded())
        return max(1, min(k, n / 3, 60))
    }

    // MARK: - Invented folders

    private struct Cluster {
        var members: [Int]
        var name: String = ""
        var primary: String = ""
        var keywords: [String] = []
    }

    private static func invent(pool: [PhotoRecord], features: [[(String, Float)]], options: Options) -> [PhotoCategory] {
        let n = pool.count
        var vocab: [String: Int] = [:]
        var names: [String] = []
        for f in features { for (l, _) in f where vocab[l] == nil { vocab[l] = names.count; names.append(l) } }
        let dims = names.count

        var df = [Int](repeating: 0, count: dims)
        var globalConf = [Double](repeating: 0, count: dims)
        for f in features { for (l, c) in f { let i = vocab[l]!; df[i] += 1; globalConf[i] += Double(c) } }
        let meanGlobal = globalConf.map { $0 / Double(n) }
        let idf = df.map { Float(log(1.0 + Double(n) / Double($0))) }

        // Sparse unit vectors.
        let vectors: [[(Int, Float)]] = features.map { f in
            var v = f.map { (vocab[$0.0]!, $0.1 * idf[vocab[$0.0]!]) }
            let norm = sqrt(v.reduce(0) { $0 + $1.1 * $1.1 })
            if norm > 0 { v = v.map { ($0.0, $0.1 / norm) } }
            return v
        }
        let sparseConf: [[(Int, Float)]] = features.map { f in f.map { (vocab[$0.0]!, $0.1) } }

        let k = targetK(n, granularity: options.granularity)
        let (assign, _) = sphericalKMeans(vectors, dims: dims, k: k)

        var clusters: [Cluster] = []
        var byLabel: [Int: Int] = [:]
        for (i, c) in assign.enumerated() {
            if byLabel[c] == nil { byLabel[c] = clusters.count; clusters.append(Cluster(members: [])) }
            clusters[byLabel[c]!].members.append(i)
        }

        // Co-occurrence helper to drop "parent" labels such as animal next to dog.
        let labelSets: [Set<Int>] = sparseConf.map { Set($0.map(\.0)) }
        func conditional(_ a: Int, given b: Int, in members: [Int]) -> Double {
            var both = 0, withB = 0
            for m in members {
                let has = labelSets[m]
                if has.contains(b) { withB += 1; if has.contains(a) { both += 1 } }
            }
            return withB == 0 ? 0 : Double(both) / Double(withB)
        }

        func name(_ c: inout Cluster) {
            var sum = [Double](repeating: 0, count: dims)
            for m in c.members { for (i, conf) in sparseConf[m] { sum[i] += Double(conf) } }
            let size = Double(c.members.count)
            var scored: [(Int, Double)] = []
            for i in 0..<dims where sum[i] > 0 {
                let mean = sum[i] / size
                let lift = mean / (meanGlobal[i] + 0.02)
                let plain = Vocabulary.technicalLabels.contains(names[i]) ? 0.7 : 1.0
                scored.append((i, mean * sqrt(lift) * plain))
            }
            scored.sort { $0.1 > $1.1 }
            guard let first = scored.first else { c.name = "Other"; c.primary = "other"; return }
            var l1 = first.0
            // Prefer the more specific word when it scores almost as well ("Dog" over "Animal").
            for (i, s) in scored.dropFirst().prefix(6) where s >= 0.85 * first.1 && df[i] < df[l1] && !Vocabulary.technicalLabels.contains(names[i]) {
                if conditional(l1, given: i, in: c.members) >= 0.9 { l1 = i; break }
            }
            var picked = [l1]
            for (i, s) in scored.prefix(7) where i != l1 && picked.count < 2 && s >= 0.55 * first.1 {
                let a = names[i], b = names[l1]
                if a.contains(b) || b.contains(a) || Vocabulary.technicalLabels.contains(a) { continue }
                // Broader label that almost always rides along with the first one: skip it.
                if df[i] >= df[l1], conditional(i, given: l1, in: c.members) >= 0.85 { continue }
                picked.append(i)
            }
            c.primary = names[l1]
            c.name = picked.map { TextTools.title(names[$0]) }.joined(separator: " & ")
            c.keywords = scored.prefix(8).map { names[$0.0] }
        }

        func centroid(_ c: Cluster) -> [Float] {
            var v = [Float](repeating: 0, count: dims)
            for m in c.members { for (i, w) in vectors[m] { v[i] += w } }
            let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
            return norm > 0 ? v.map { $0 / norm } : v
        }

        let minSize = max(3, min(20, n / 400))
        for _ in 0..<4 {
            for i in clusters.indices { name(&clusters[i]) }
            var changed = false
            // Same leading label -> one folder.
            var seen: [String: Int] = [:]
            var merged: [Cluster] = []
            for c in clusters {
                if let at = seen[c.primary] { merged[at].members += c.members; changed = true }
                else { seen[c.primary] = merged.count; merged.append(c) }
            }
            clusters = merged
            // Tiny folders fold into their closest neighbour.
            if clusters.count > 1 {
                let cents = clusters.map(centroid)
                var target = Array(clusters.indices)
                for (i, c) in clusters.enumerated() where c.members.count < minSize {
                    var best = -1, bestSim: Float = -1
                    for (j, other) in clusters.enumerated() where j != i && other.members.count >= minSize {
                        let s = zip(cents[i], cents[j]).reduce(Float(0)) { $0 + $1.0 * $1.1 }
                        if s > bestSim { bestSim = s; best = j }
                    }
                    if best >= 0 { target[i] = best; changed = true }
                }
                if changed {
                    var next: [Int: Cluster] = [:]
                    for (i, c) in clusters.enumerated() {
                        let t = target[i]
                        if next[t] == nil { next[t] = Cluster(members: []) }
                        next[t]!.members += c.members
                    }
                    clusters = next.keys.sorted().map { next[$0]! }
                }
            }
            if !changed { break }
        }
        for i in clusters.indices { name(&clusters[i]) }

        return clusters.map { c -> PhotoCategory in
            let cent = centroid(c)
            let members = c.members.sorted { (pool[$0].date ?? .distantPast) > (pool[$1].date ?? .distantPast) }
            let bySim = c.members.sorted { a, b in
                let sa = vectors[a].reduce(Float(0)) { $0 + $1.1 * cent[$1.0] }
                let sb = vectors[b].reduce(Float(0)) { $0 + $1.1 * cent[$1.0] }
                return sa > sb
            }
            let covers = pickCovers(bySim.map { pool[$0] })
            let id = "cat." + c.primary
            let recs = members.map { pool[$0] }
            let label = options.customNames[id] ?? c.name
            return PhotoCategory(
                id: id, name: label, keywords: c.keywords, symbol: Vocabulary.symbol(for: c.keywords),
                kind: .invented, photoIDs: recs.map(\.id), coverIDs: covers,
                groups: Grouper.groups(categoryID: id, records: recs, categoryKeywords: Set(c.keywords)))
        }
        .sorted { $0.photoIDs.count > $1.photoIDs.count }
    }

    private static func special(id: String, name: String, symbol: String, kind: PhotoCategory.Kind,
                                records: [PhotoRecord], options: Options) -> PhotoCategory {
        PhotoCategory(id: id, name: options.customNames[id] ?? name, keywords: [], symbol: symbol, kind: kind,
                      photoIDs: records.map(\.id), coverIDs: pickCovers(records),
                      groups: Grouper.groups(categoryID: id, records: records, categoryKeywords: []))
    }

    /// Up to four covers, preferring photos from different days.
    static func pickCovers(_ ranked: [PhotoRecord]) -> [String] {
        var out: [String] = []
        var days = Set<Int>()
        for r in ranked.prefix(60) {
            let day = Int((r.date?.timeIntervalSince1970 ?? 0) / 86_400)
            if days.insert(day).inserted { out.append(r.id) }
            if out.count == 4 { return out }
        }
        for r in ranked.prefix(60) where !out.contains(r.id) {
            out.append(r.id)
            if out.count == 4 { break }
        }
        return out
    }

    // MARK: - Clustering

    /// Deterministic spherical k-means with k-means++ seeding over sparse unit vectors.
    static func sphericalKMeans(_ vectors: [[(Int, Float)]], dims: Int, k: Int, iterations: Int = 25,
                                seed: UInt64 = 0x5EED) -> ([Int], [[Float]]) {
        let n = vectors.count
        guard n > 0, dims > 0, k > 1 else { return ([Int](repeating: 0, count: n), []) }
        var rng = SplitMix64(seed: seed)
        func dot(_ v: [(Int, Float)], _ c: [Float]) -> Float { v.reduce(0) { $0 + $1.1 * c[$1.0] } }
        func dense(_ v: [(Int, Float)]) -> [Float] {
            var d = [Float](repeating: 0, count: dims); for (i, w) in v { d[i] = w }; return d
        }

        var centroids: [[Float]] = [dense(vectors[Int(rng.next() % UInt64(n))])]
        var best = vectors.map { dot($0, centroids[0]) }
        while centroids.count < k {
            let weights = best.map { Double(max(0, 1 - $0)) * Double(max(0, 1 - $0)) }
            let total = weights.reduce(0, +)
            var pick = 0
            if total <= 0 { pick = Int(rng.next() % UInt64(n)) } else {
                var r = Double(rng.next() % 1_000_000) / 1_000_000 * total
                for (i, w) in weights.enumerated() { r -= w; if r <= 0 { pick = i; break } }
            }
            let c = dense(vectors[pick])
            centroids.append(c)
            for i in 0..<n { best[i] = max(best[i], dot(vectors[i], c)) }
        }

        var assign = [Int](repeating: -1, count: n)
        var sims = [Float](repeating: 0, count: n)
        for _ in 0..<iterations {
            var changes = 0
            for i in 0..<n {
                var bi = 0, bs: Float = -2
                for (ci, c) in centroids.enumerated() {
                    let s = dot(vectors[i], c)
                    if s > bs { bs = s; bi = ci }
                }
                sims[i] = bs
                if assign[i] != bi { assign[i] = bi; changes += 1 }
            }
            var sums = [[Float]](repeating: [Float](repeating: 0, count: dims), count: k)
            var counts = [Int](repeating: 0, count: k)
            for i in 0..<n {
                counts[assign[i]] += 1
                for (d, w) in vectors[i] { sums[assign[i]][d] += w }
            }
            for ci in 0..<k {
                if counts[ci] == 0 {
                    // Empty folder: restart it on the worst-fitting photo.
                    let worst = sims.indices.min { sims[$0] < sims[$1] } ?? 0
                    sums[ci] = dense(vectors[worst]); sims[worst] = 2
                }
                let norm = sqrt(sums[ci].reduce(0) { $0 + $1 * $1 })
                centroids[ci] = norm > 0 ? sums[ci].map { $0 / norm } : sums[ci]
            }
            if changes == 0 { break }
        }
        return (assign, centroids)
    }
}

struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
