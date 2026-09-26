import Foundation
import os

/// What the app learned about each photo, kept in one file on the phone (left out of iCloud backups).
actor IndexStore {
    private var records: [String: PhotoRecord] = [:]
    private var dirty = false
    private let folder: URL
    private let file: URL
    private let log = Logger(subsystem: "com.stproperties.photofolders", category: "store")

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("PhotoFolders", isDirectory: true)
        file = folder.appendingPathComponent("index.json")
    }

    func load() -> [String: PhotoRecord] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        do {
            let list = try JSONDecoder().decode([PhotoRecord].self, from: data)
            records = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            log.error("index unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
            records = [:]
        }
        return records
    }

    func upsert(_ list: [PhotoRecord]) {
        for r in list { records[r.id] = r }
        dirty = true
    }

    func remove(_ ids: [String]) {
        for id in ids { records[id] = nil }
        dirty = true
    }

    func clear() {
        records = [:]
        dirty = true
    }

    func save() {
        guard dirty else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var dir = folder
            try? dir.setResourceValues(values)
            let data = try JSONEncoder().encode(Array(records.values))
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            dirty = false
            log.info("saved \(self.records.count) photos")
        } catch {
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
