import Foundation

/// Splits one folder into sub-folders: outings/events when there are few, months or years when there are many.
enum Grouper {
    static let gapHours: Double = 6

    static func groups(categoryID: String, records: [PhotoRecord], categoryKeywords: Set<String>,
                       calendar: Calendar = .current) -> [PhotoGroup] {
        guard !records.isEmpty else { return [] }
        let sorted = records.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        if sorted.count <= 8 {
            return [make(id: categoryID + ".all", title: "All photos", records: sorted, hint: nil)]
        }
        let dated = sorted.filter { $0.date != nil }
        let undated = sorted.filter { $0.date == nil }
        let catMean = meanConfidence(sorted)

        var buckets: [(key: String, title: String, records: [PhotoRecord])] = eventBuckets(dated, calendar: calendar)
        if buckets.count > 30 { buckets = periodBuckets(dated, component: .month, calendar: calendar) }
        if buckets.count > 48 { buckets = periodBuckets(dated, component: .year, calendar: calendar) }

        var out = buckets.map { b in
            make(id: categoryID + "." + b.key, title: b.title, records: b.records,
                 hint: hint(for: b.records, categoryMean: catMean, exclude: categoryKeywords))
        }
        if !undated.isEmpty { out.append(make(id: categoryID + ".undated", title: "No date", records: undated, hint: nil)) }
        return out
    }

    private static func make(id: String, title: String, records: [PhotoRecord], hint: String?) -> PhotoGroup {
        let count = records.count == 1 ? "1 photo" : "\(records.count) photos"
        let subtitle = hint.map { "\(count) · \(TextTools.title($0))" } ?? count
        return PhotoGroup(id: id, title: title, subtitle: subtitle, photoIDs: records.map(\.id), coverIDs: spread(records.map(\.id)))
    }

    /// Four covers spread across the group, not the first four shots of a burst.
    static func spread(_ ids: [String]) -> [String] {
        guard ids.count > 4 else { return ids }
        return (0..<4).map { ids[$0 * (ids.count - 1) / 3] }
    }

    private static func eventBuckets(_ dated: [PhotoRecord], calendar: Calendar) -> [(key: String, title: String, records: [PhotoRecord])] {
        var events: [[PhotoRecord]] = []
        var current: [PhotoRecord] = []
        for r in dated {
            if let last = current.last?.date, let d = r.date, last.timeIntervalSince(d) > gapHours * 3600 {
                events.append(current); current = []
            }
            current.append(r)
        }
        if !current.isEmpty { events.append(current) }

        var out: [(key: String, title: String, records: [PhotoRecord], newest: Date)] = []
        var leftovers: [String: [PhotoRecord]] = [:]
        for e in events {
            guard let newest = e.first?.date, let oldest = e.last?.date else { continue }
            if e.count >= 3 {
                out.append((key: "e\(Int(newest.timeIntervalSince1970))", title: rangeTitle(oldest, newest, calendar: calendar),
                            records: e, newest: newest))
            } else {
                for r in e { leftovers[monthKey(r.date!, calendar), default: []].append(r) }
            }
        }
        for (key, rs) in leftovers {
            guard let d = rs.first?.date else { continue }
            out.append((key: "m" + key, title: "More from " + monthTitle(d, calendar), records: rs, newest: d))
        }
        return out.sorted { $0.newest > $1.newest }.map { (key: $0.key, title: $0.title, records: $0.records) }
    }

    private static func periodBuckets(_ dated: [PhotoRecord], component: Calendar.Component,
                                      calendar: Calendar) -> [(key: String, title: String, records: [PhotoRecord])] {
        var order: [String] = []
        var map: [String: [PhotoRecord]] = [:]
        for r in dated {
            let key = component == .month ? monthKey(r.date!, calendar) : String(calendar.component(.year, from: r.date!))
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(r)
        }
        return order.map { key in
            let rs = map[key]!
            let title = component == .month ? monthTitle(rs[0].date!, calendar) : key
            return (key: (component == .month ? "m" : "y") + key, title: title, records: rs)
        }
    }

    private static func monthKey(_ d: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: d)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    private static func monthTitle(_ d: Date, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: d)
    }

    static func rangeTitle(_ start: Date, _ end: Date, calendar: Calendar) -> String {
        if calendar.isDate(start, inSameDayAs: end) {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.setLocalizedDateFormatFromTemplate("EEE MMM d yyyy")
            return f.string(from: start)
        }
        let f = DateIntervalFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: start, to: end)
    }

    private static func meanConfidence(_ records: [PhotoRecord]) -> [String: Double] {
        var sum: [String: Double] = [:]
        for r in records { for l in r.labels { sum[l.name, default: 0] += Double(l.confidence) } }
        let n = Double(max(1, records.count))
        return sum.mapValues { $0 / n }
    }

    /// The label that makes this group different from its folder ("Snow" inside "Dog").
    private static func hint(for records: [PhotoRecord], categoryMean: [String: Double], exclude: Set<String>) -> String? {
        let mean = meanConfidence(records)
        var best: (String, Double)?
        for (label, m) in mean where m >= 0.3 && !exclude.contains(label) && !Vocabulary.genericLabels.contains(label) {
            let lift = m / ((categoryMean[label] ?? 0) + 0.05)
            let score = m * lift
            if lift > 1.3, score > (best?.1 ?? 0) { best = (label, score) }
        }
        return best?.0
    }
}
