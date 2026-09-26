import XCTest
@testable import PhotoFolders

private func rec(_ id: String, _ labels: [(String, Float)], daysAgo: Double = 0, hour: Double = 12,
                 text: String = "", traits: [String] = [], faces: Int = 0, now: Date) -> PhotoRecord {
    PhotoRecord(id: id, date: now.addingTimeInterval(-daysAgo * 86_400 + hour * 3600),
                labels: labels.map { LabelHit(name: $0.0, confidence: $0.1) }, text: text,
                traits: traits, faceCount: faces, latitude: nil, longitude: nil, version: 1)
}

/// Fake meaning model: a few hand-made neighbours.
private final class FakeMatcher: SemanticMatcher {
    let table: [String: [String]] = ["hound": ["dog", "puppy"], "seashore": ["beach", "shore"], "supper": ["dinner", "food"]]
    func neighbors(of word: String, limit: Int) -> [String] { table[word] ?? [] }
    func closeness(_ a: String, _ b: String) -> Double? { nil }
}

final class LibraryFixture {
    let now: Date
    let calendar: Calendar
    var records: [PhotoRecord] = []

    init() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Edmonton")!
        calendar = cal
        now = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12))!
        var n = 0
        func add(_ count: Int, _ labels: [(String, Float)], startDay: Double, text: String = "", traits: [String] = [], faces: Int = 0) {
            for i in 0..<count {
                n += 1
                // Outings of 5 photos taken minutes apart, four days between outings.
                let day = startDay + Double(i / 5) * 4
                records.append(rec("p\(n)", labels, daysAgo: day, hour: 10 + Double(i % 5) * 0.1,
                                   text: text, traits: traits, faces: faces, now: now))
            }
        }
        add(30, [("animal", 0.95), ("dog", 0.93), ("canine", 0.9), ("mammal", 0.9), ("grass", 0.4)], startDay: 1)
        add(30, [("beach", 0.9), ("sea", 0.8), ("sand", 0.7), ("sky", 0.6), ("shore", 0.6)], startDay: 70)   // mid-July 2026
        add(30, [("food", 0.9), ("dish", 0.7), ("table", 0.3)], startDay: 2)
        add(12, [("document", 0.9), ("text", 0.8), ("receipt", 0.6)], startDay: 3, text: "COSTCO WHOLESALE total 84.12 thank you")
        add(6, [("text", 0.5)], startDay: 4, traits: [Trait.screenshot])
        add(3, [], startDay: 5)
        add(6, [("animal", 0.95), ("cat", 0.93), ("feline", 0.9), ("mammal", 0.9)], startDay: 6)
    }
}

final class CategoryEngineTests: XCTestCase {
    func testInventsOneFolderPerSubjectAndKeepsScreenshotsApart() {
        let f = LibraryFixture()
        let cats = CategoryEngine.build(records: f.records)
        let names = cats.map(\.name)
        XCTAssertTrue(names.contains { $0.hasPrefix("Dog") }, "\(names)")
        XCTAssertTrue(names.contains { $0.hasPrefix("Beach") }, "\(names)")
        XCTAssertTrue(names.contains { $0.hasPrefix("Food") }, "\(names)")
        XCTAssertTrue(names.contains { $0.hasPrefix("Document") || $0.hasPrefix("Receipt") }, "\(names)")
        XCTAssertEqual(cats.first { $0.kind == .screenshots }?.photoIDs.count, 6)
        XCTAssertEqual(cats.first { $0.kind == .unsorted }?.photoIDs.count, 3)
        // Every photo lands in exactly one folder.
        let all = cats.flatMap(\.photoIDs)
        XCTAssertEqual(all.count, f.records.count)
        XCTAssertEqual(Set(all).count, f.records.count)
        // The dog folder is not polluted by beach photos.
        let dog = cats.first { $0.name.hasPrefix("Dog") }!
        XCTAssertEqual(dog.photoIDs.count, 30)
        XCTAssertFalse(dog.name.contains("Animal"), "parent label should not be in the name: \(dog.name)")
        XCTAssertFalse(dog.name.contains("Canine"), "prefer the everyday word: \(dog.name)")
        XCTAssertTrue(names.contains { $0.hasPrefix("Cat") }, "\(names)")
        XCTAssertEqual(dog.coverIDs.count, 4)
        XCTAssertEqual(dog.symbol, "pawprint.fill")
    }

    func testGroupsFollowOutings() {
        let f = LibraryFixture()
        let cats = CategoryEngine.build(records: f.records)
        let dog = cats.first { $0.name.hasPrefix("Dog") }!
        XCTAssertEqual(dog.groups.count, 6, dog.groups.map(\.title).description)
        XCTAssertTrue(dog.groups.allSatisfy { $0.photoIDs.count == 5 })
        XCTAssertEqual(Set(dog.groups.flatMap(\.photoIDs)), Set(dog.photoIDs))
    }

    func testCustomNameSticks() {
        let f = LibraryFixture()
        let first = CategoryEngine.build(records: f.records).first { $0.name.hasPrefix("Dog") }!
        let renamed = CategoryEngine.build(records: f.records, options: .init(granularity: 1, customNames: [first.id: "Rex"]))
        XCTAssertTrue(renamed.contains { $0.name == "Rex" && $0.id == first.id })
    }

    func testScalesToALargeLibrary() {
        let f = LibraryFixture()
        var big: [PhotoRecord] = []
        for copy in 0..<150 {
            for r in f.records { var c = r; c.id = "\(copy)-\(r.id)"; big.append(c) }
        }
        let started = Date()
        let cats = CategoryEngine.build(records: big)
        let index = SearchIndex(records: big, categories: cats, matcher: nil)
        let built = Date().timeIntervalSince(started)
        XCTAssertGreaterThan(cats.count, 3)
        let searchStart = Date()
        _ = index.search("dog on the grass", now: f.now, calendar: f.calendar)
        let searched = Date().timeIntervalSince(searchStart)
        print("PERF \(big.count) photos: folders+index \(built)s, one search \(searched)s")
        XCTAssertLessThan(built, 30)
        XCTAssertLessThan(searched, 1)
    }

    func testTargetK() {
        XCTAssertEqual(CategoryEngine.targetK(0, granularity: 1), 0)
        XCTAssertEqual(CategoryEngine.targetK(4, granularity: 1), 1)
        XCTAssertGreaterThan(CategoryEngine.targetK(10_000, granularity: 1), CategoryEngine.targetK(1_000, granularity: 1))
        XCTAssertLessThanOrEqual(CategoryEngine.targetK(1_000_000, granularity: 2), 60)
    }
}

final class SearchIndexTests: XCTestCase {
    private var f: LibraryFixture!
    private var index: SearchIndex!

    override func setUp() {
        f = LibraryFixture()
        let cats = CategoryEngine.build(records: f.records)
        index = SearchIndex(records: f.records, categories: cats, matcher: FakeMatcher())
    }

    private func ids(_ q: String) -> Set<String> {
        Set(index.search(q, now: f.now, calendar: f.calendar).hits.filter(\.matchedAll).map(\.id))
    }

    private func labelled(_ label: String) -> Set<String> {
        Set(f.records.filter { $0.labels.contains { $0.name == label } }.map(\.id))
    }

    func testPlainWord() { XCTAssertEqual(ids("dog "), labelled("dog")) }
    func testPlural() { XCTAssertEqual(ids("dogs "), labelled("dog")) }
    func testSynonym() { XCTAssertEqual(ids("puppy "), labelled("dog")) }
    func testMeaningModel() { XCTAssertEqual(ids("seashore "), labelled("beach")) }
    func testTypo() { XCTAssertEqual(ids("beahc "), labelled("beach")) }
    func testPrefixWhileTyping() { XCTAssertTrue(labelled("beach").isSubset(of: ids("bea"))) }
    func testNaturalSentence() { XCTAssertEqual(ids("show me photos of my dog "), labelled("dog")) }
    func testTextInsidePhotos() { XCTAssertEqual(ids("costco receipt "), labelled("receipt")) }
    func testScreenshots() { XCTAssertEqual(ids("screenshots ").count, 6) }

    func testDates() {
        let r = index.search("beach this summer", now: f.now, calendar: f.calendar)
        XCTAssertEqual(r.dateLabel, "Summer 2026")
        XCTAssertEqual(Set(r.hits.filter(\.matchedAll).map(\.id)), labelled("beach"))
        XCTAssertTrue(ids("dog last summer").isEmpty, "dog photos are all from September")
        XCTAssertTrue(ids("beach last summer").count == 30)
        XCTAssertEqual(ids("dog september 2026"), labelled("dog"))
    }

    func testUnknownWordFindsNothing() {
        XCTAssertTrue(index.search("zebra ", now: f.now, calendar: f.calendar).hits.isEmpty)
    }

    func testTwoThingsRanksPhotosWithBothFirst() {
        let r = index.search("dog grass ", now: f.now, calendar: f.calendar)
        XCTAssertEqual(Set(r.hits.filter(\.matchedAll).map(\.id)), labelled("dog"))
    }
}

final class DateQueryParserTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Edmonton")!
        return c
    }()
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12))! }
    private func parse(_ s: String) -> DateQueryParser.Result { DateQueryParser(now: now, calendar: cal).parse(s) }
    private func ymd(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    func testLastSummer() {
        let r = parse("dogs last summer")
        // Said in late September, "last summer" is the summer that just ended.
        XCTAssertEqual(ymd(r.range!.start), "2026-6-1")
        XCTAssertEqual(ymd(r.range!.end), "2026-9-1")
        XCTAssertEqual(r.remaining, ["dogs"])
    }

    func testMonthAndYear() {
        let r = parse("beach july 2023")
        XCTAssertEqual(ymd(r.range!.start), "2023-7-1")
        XCTAssertEqual(r.remaining, ["beach"])
    }

    func testBareMonthMeansMostRecent() {
        XCTAssertEqual(ymd(parse("october").range!.start), "2025-10-1")
        XCTAssertEqual(ymd(parse("august").range!.start), "2026-8-1")
    }

    func testMayIsOnlyAMonthWhenItLooksLikeOne() {
        XCTAssertNil(parse("may").range)
        XCTAssertEqual(ymd(parse("in may").range!.start), "2026-5-1")
        XCTAssertEqual(ymd(parse("may 2024").range!.start), "2024-5-1")
    }

    func testAgoAndYesterday() {
        XCTAssertEqual(ymd(parse("yesterday").range!.start), "2026-9-25")
        XCTAssertEqual(ymd(parse("2 years ago").range!.start), "2024-1-1")
        XCTAssertEqual(parse("3 weeks ago").remaining, [])
    }

    func testYear() {
        let r = parse("christmas 2024")
        XCTAssertEqual(ymd(r.range!.start), "2024-1-1")
        XCTAssertEqual(r.remaining, ["christmas"])
    }
}

final class TextToolsTests: XCTestCase {
    func testEditDistance() {
        XCTAssertEqual(TextTools.editDistance("beach", "beahc"), 1)
        XCTAssertEqual(TextTools.editDistance("kitten", "sitting"), 3)
        XCTAssertEqual(TextTools.editDistance("dog", "dog"), 0)
        XCTAssertEqual(TextTools.editDistance("abc", "abcdef", limit: 1), 2)
    }

    func testSingular() {
        XCTAssertEqual(TextTools.singular("puppies"), "puppy")
        XCTAssertEqual(TextTools.singular("beaches"), "beach")
        XCTAssertEqual(TextTools.singular("dogs"), "dog")
        XCTAssertEqual(TextTools.singular("glass"), "glass")
        XCTAssertEqual(TextTools.singular("children"), "child")
    }
}

final class CustomFolderTests: XCTestCase {
    private var f: LibraryFixture!
    private var looks: [String: LookVector] = [:]

    override func setUp() {
        f = LibraryFixture()
        looks = [:]
        for (i, r) in f.records.enumerated() {
            let n = Int8(i % 7)
            var v = [Int8](repeating: 0, count: 8)
            if r.labels.contains(where: { $0.name == "dog" }) { v[0] = 120; v[1] = n }
            else if r.labels.contains(where: { $0.name == "cat" }) { v[2] = 120; v[3] = n }
            else { v[4] = 100; v[5] = n; v[6] = Int8(i % 3) }
            looks[r.id] = LookVector(values: v)
        }
    }

    private func labelled(_ label: String) -> Set<String> {
        Set(f.records.filter { $0.labels.contains { $0.name == label } }.map(\.id))
    }

    func testDescriptionFillsFolderAndTakesPhotosOutOfInventedFolders() {
        let folder = CustomFolder(name: "Receipts", describe: "receipts")
        let out = CategoryEngine.buildAll(records: f.records, looks: looks, customFolders: [folder],
                                          options: .init(), matcher: nil, now: f.now)
        let mine = out.categories.first!
        XCTAssertEqual(mine.kind, .custom)
        XCTAssertEqual(mine.name, "Receipts")
        XCTAssertEqual(Set(mine.photoIDs), labelled("receipt"))
        XCTAssertFalse(out.categories.dropFirst().contains { $0.name.hasPrefix("Document") }, out.categories.map(\.name).description)
        let all = out.categories.flatMap(\.photoIDs)
        XCTAssertEqual(all.count, f.records.count, "every photo in exactly one folder")
        XCTAssertEqual(Set(all).count, f.records.count)
        // Its name is searchable like any folder.
        XCTAssertTrue(out.index.search("receipts ", now: f.now, calendar: f.calendar).categoryIDs.contains(folder.categoryID))
    }

    func testExamplesFindLookAlikes() {
        let dogs = Array(labelled("dog")).sorted()
        let folder = CustomFolder(name: "Rex", exampleIDs: [dogs[0], dogs[5]])
        let r = CustomFolderResolver.resolve(folder, records: f.records, search: nil, looks: looks, now: f.now)
        XCTAssertEqual(Set(r.members), labelled("dog"))
    }

    func testSingleExampleLoose() {
        let dogs = Array(labelled("dog")).sorted()
        var folder = CustomFolder(name: "Rex", exampleIDs: [dogs[0]])
        folder.closeness = 1
        let r = CustomFolderResolver.resolve(folder, records: f.records, search: nil, looks: looks, now: f.now)
        XCTAssertEqual(Set(r.members), labelled("dog"))
        folder.closeness = 0
        let strict = CustomFolderResolver.resolve(folder, records: f.records, search: nil, looks: looks, now: f.now)
        XCTAssertTrue(Set(strict.members).isSubset(of: labelled("dog")))
        XCTAssertLessThanOrEqual(strict.members.count, r.members.count)
    }

    func testLeftOutPhotosStayOut() {
        let receipts = Array(labelled("receipt")).sorted()
        let folder = CustomFolder(name: "Receipts", describe: "receipts", excluded: [receipts[0]])
        let r = CustomFolderResolver.resolve(folder, records: f.records,
                                             search: SearchIndex(records: f.records, categories: [], matcher: nil),
                                             looks: looks, now: f.now)
        XCTAssertEqual(r.candidates.count, 12)
        XCTAssertEqual(r.members.count, 11)
        XCTAssertFalse(r.members.contains(receipts[0]))
    }

    func testLookVectorRoundTrip() {
        let v = LookVector.quantize([0.1, -0.2, 0.05, 0.3])!
        XCTAssertEqual(LookVector(data: v.data)!.values, v.values)
        XCTAssertEqual(v.similarity(v), 1, accuracy: 0.001)
    }
}
