import Foundation

/// Pulls time phrases out of a search ("dogs last summer", "beach july 2023", "3 weeks ago").
struct DateQueryParser {
    var now: Date = Date()
    var calendar: Calendar = .current

    struct Result {
        var range: DateInterval?
        var label: String?
        var remaining: [String]
    }

    static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4,
        "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9,
        "sep": 9, "sept": 9, "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12,
    ]
    /// Month words that are also ordinary words; they count only with a year or "in/during/last…".
    static let ambiguousMonths: Set<String> = ["may", "march", "mar", "jan", "sat"]
    static let seasons: [String: Int] = ["spring": 3, "summer": 6, "fall": 9, "autumn": 9, "winter": 12]
    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "couple": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
    ]
    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July",
                                     "August", "September", "October", "November", "December"]
    private static let qualifiers: Set<String> = ["in", "during", "from", "of", "since", "around", "last", "this", "the"]

    func parse(_ query: String) -> Result { parse(words: TextTools.words(query)) }

    func parse(words: [String]) -> Result {
        var consumed = Set<Int>()
        var found: [(DateInterval, String)] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            let next: String? = i + 1 < words.count ? words[i + 1] : nil
            let prev: String? = i > 0 ? words[i - 1] : nil

            if w == "today" || w == "tonight" {
                found.append((dayInterval(now), "Today")); consumed.insert(i); i += 1; continue
            }
            if w == "yesterday", let d = calendar.date(byAdding: .day, value: -1, to: now) {
                found.append((dayInterval(d), "Yesterday")); consumed.insert(i); i += 1; continue
            }
            if ["this", "last", "past", "previous"].contains(w), let n = next, let hit = relative(w, n) {
                found.append(hit); consumed.formUnion([i, i + 1]); i += 2; continue
            }
            if let count = Int(w) ?? Self.numberWords[w], count > 0, count < 200,
               let unitWord = next, let unit = Self.unit(unitWord),
               i + 2 < words.count, words[i + 2] == "ago",
               let target = calendar.date(byAdding: unit, value: -count, to: now),
               let interval = calendar.dateInterval(of: unit, for: target) {
                found.append((interval, "\(count) \(unitWord) ago")); consumed.formUnion([i, i + 1, i + 2]); i += 3; continue
            }
            if let m = Self.months[w] {
                let y = Self.year(next)
                if !Self.ambiguousMonths.contains(w) || y != nil || Self.qualifiers.contains(prev ?? "") {
                    if let y, let interval = monthInterval(year: y, month: m) {
                        found.append((interval, "\(Self.monthNames[m - 1]) \(y)")); consumed.formUnion([i, i + 1]); i += 2; continue
                    }
                    if let interval = recentMonth(m, includeCurrent: true) {
                        found.append((interval, "\(Self.monthNames[m - 1]) \(calendar.component(.year, from: interval.start))"))
                        consumed.insert(i); i += 1; continue
                    }
                }
            }
            if let s = Self.seasons[w] {
                let y = Self.year(next)
                if w != "fall" || y != nil || ["in", "during", "the"].contains(prev ?? "") {
                    if let y {
                        let startYear = s == 12 ? y - 1 : y
                        if let interval = seasonInterval(startMonth: s, startYear: startYear) {
                            found.append((interval, "\(w.capitalized) \(y)")); consumed.formUnion([i, i + 1]); i += 2; continue
                        }
                    } else if let interval = recentSeason(s, includeCurrent: true) {
                        found.append((interval, seasonLabel(w, interval))); consumed.insert(i); i += 1; continue
                    }
                }
            }
            if let y = Self.year(w), let interval = yearInterval(y) {
                found.append((interval, String(y))); consumed.insert(i); i += 1; continue
            }
            i += 1
        }

        var range: DateInterval?
        var labels: [String] = []
        for (interval, label) in found {
            if let current = range, let both = current.intersection(with: interval), both.duration > 0 {
                range = both
            } else {
                range = interval
                if !labels.isEmpty { labels.removeAll() }
            }
            labels.append(label)
        }
        let remaining = words.enumerated().filter { !consumed.contains($0.offset) }.map(\.element)
        return Result(range: range, label: labels.isEmpty ? nil : labels.joined(separator: " · "), remaining: remaining)
    }

    // MARK: - Pieces

    private func relative(_ qualifier: String, _ word: String) -> (DateInterval, String)? {
        let isThis = qualifier == "this"
        let rolling = qualifier == "past"
        let label = "\(qualifier.capitalized) \(word)"
        if let unit = Self.unit(word), [Calendar.Component.day, .weekOfYear, .month, .year].contains(unit) {
            if rolling {
                guard let start = calendar.date(byAdding: unit, value: -1, to: now) else { return nil }
                return (DateInterval(start: start, end: now), label)
            }
            let anchor = isThis ? now : (calendar.date(byAdding: unit, value: -1, to: now) ?? now)
            guard let interval = calendar.dateInterval(of: unit, for: anchor) else { return nil }
            return (interval, label)
        }
        if word == "weekend" {
            if isThis, calendar.isDateInWeekend(now), let w = calendar.dateIntervalOfWeekend(containing: now) {
                return (w, label)
            }
            let direction: Calendar.SearchDirection = isThis ? .forward : .backward
            guard let w = calendar.nextWeekend(startingAfter: now, direction: direction) else { return nil }
            return (w, label)
        }
        if let s = Self.seasons[word], let interval = recentSeason(s, includeCurrent: isThis) {
            return (interval, seasonLabel(word, interval))
        }
        if let m = Self.months[word], let interval = recentMonth(m, includeCurrent: isThis) {
            return (interval, "\(Self.monthNames[m - 1]) \(calendar.component(.year, from: interval.start))")
        }
        return nil
    }

    private func seasonLabel(_ word: String, _ interval: DateInterval) -> String {
        let endYear = calendar.component(.year, from: interval.end.addingTimeInterval(-1))
        return "\(word.capitalized) \(endYear)"
    }

    private static func unit(_ w: String) -> Calendar.Component? {
        switch w {
        case "day", "days": return .day
        case "week", "weeks": return .weekOfYear
        case "month", "months": return .month
        case "year", "years": return .year
        default: return nil
        }
    }

    private static func year(_ s: String?) -> Int? {
        guard let s, s.count == 4, let y = Int(s), (1900...2100).contains(y) else { return nil }
        return y
    }

    private func dayInterval(_ d: Date) -> DateInterval {
        calendar.dateInterval(of: .day, for: d) ?? DateInterval(start: d, duration: 86_400)
    }

    private func monthInterval(year: Int, month: Int) -> DateInterval? {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        return calendar.dateInterval(of: .month, for: start)
    }

    private func yearInterval(_ y: Int) -> DateInterval? {
        guard let start = calendar.date(from: DateComponents(year: y, month: 1, day: 1)) else { return nil }
        return calendar.dateInterval(of: .year, for: start)
    }

    private func seasonInterval(startMonth: Int, startYear: Int) -> DateInterval? {
        guard let start = calendar.date(from: DateComponents(year: startYear, month: startMonth, day: 1)),
              let end = calendar.date(byAdding: .month, value: 3, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Most recent month with that number. includeCurrent: the running month counts.
    private func recentMonth(_ month: Int, includeCurrent: Bool) -> DateInterval? {
        let year = calendar.component(.year, from: now)
        for y in stride(from: year, through: year - 2, by: -1) {
            guard let interval = monthInterval(year: y, month: month) else { continue }
            if includeCurrent ? interval.start <= now : interval.end <= now { return interval }
        }
        return nil
    }

    private func recentSeason(_ startMonth: Int, includeCurrent: Bool) -> DateInterval? {
        let year = calendar.component(.year, from: now)
        for y in stride(from: year, through: year - 3, by: -1) {
            guard let interval = seasonInterval(startMonth: startMonth, startYear: y) else { continue }
            if includeCurrent ? interval.start <= now : interval.end <= now { return interval }
        }
        return nil
    }
}
