import Foundation

enum TextTools {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Lowercase, no accents, no width variants.
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: posix).lowercased()
    }

    /// Words of a string, folded. Letters and digits only.
    static func words(_ s: String) -> [String] {
        fold(s).split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// Vision identifiers look like "blue_sky"; we keep "blue sky".
    static func prettyLabel(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ").lowercased()
    }

    /// "blue sky" -> "Blue Sky"
    static func title(_ s: String) -> String {
        s.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static let irregular: [String: String] = [
        "children": "child", "men": "man", "women": "woman", "people": "people", "mice": "mouse",
        "teeth": "tooth", "feet": "foot", "geese": "goose", "leaves": "leaf", "knives": "knife",
        "wolves": "wolf", "shelves": "shelf", "loaves": "loaf", "puppies": "puppy", "babies": "baby",
        "glasses": "glasses", "clothes": "clothes", "fireworks": "fireworks", "sunglasses": "sunglasses",
        "dishes": "dish", "boxes": "box", "buses": "bus", "beaches": "beach", "sandwiches": "sandwich",
    ]

    /// Cheap English singular, good enough for matching search words to labels.
    static func singular(_ w: String) -> String {
        if let s = irregular[w] { return s }
        guard w.count > 3 else { return w }
        if w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.hasSuffix("ches") || w.hasSuffix("shes") || w.hasSuffix("xes") || w.hasSuffix("sses") {
            return String(w.dropLast(2))
        }
        if w.hasSuffix("ss") || w.hasSuffix("us") || w.hasSuffix("is") || w.hasSuffix("ous") { return w }
        if w.hasSuffix("s") { return String(w.dropLast()) }
        return w
    }

    /// Optimal-string-alignment distance (a swap of two letters counts as one typo).
    /// Returns limit + 1 as soon as the distance is known to exceed `limit`.
    static func editDistance(_ a: String, _ b: String, limit: Int = Int.max) -> Int {
        let a = Array(a), b = Array(b)
        let n = a.count, m = b.count
        if abs(n - m) > limit { return limit == Int.max ? abs(n - m) : limit + 1 }
        if n == 0 { return m }
        if m == 0 { return n }
        var prev2 = [Int](repeating: 0, count: m + 1)
        var prev = Array(0...m)
        var cur = [Int](repeating: 0, count: m + 1)
        for i in 1...n {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...m {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var v = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    v = Swift.min(v, prev2[j - 2] + 1)
                }
                cur[j] = v
                rowMin = Swift.min(rowMin, v)
            }
            if limit != Int.max, rowMin > limit { return limit + 1 }
            prev2 = prev
            prev = cur
        }
        return prev[m]
    }
}
