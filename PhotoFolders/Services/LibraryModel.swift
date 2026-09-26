import BackgroundTasks
import Foundation
import os
import Photos
import SwiftUI
import UIKit

/// The app's brain: keeps the photo index in step with the library and rebuilds folders and search.
@MainActor
final class LibraryModel: ObservableObject {
    static let shared = LibraryModel()
    static let backgroundTaskID = "com.stproperties.photofolders.index"

    enum Access { case unknown, denied, limited, full }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var categories: [PhotoCategory] = []
    @Published private(set) var isIndexing = false
    @Published private(set) var progressDone = 0
    @Published private(set) var progressTotal = 0
    @Published private(set) var totalPhotos = 0
    @Published private(set) var indexedPhotos = 0
    @Published private(set) var searchIndex: SearchIndex?
    @Published private(set) var isBuilding = false
    @Published private(set) var loaded = false
    @Published var granularity: Double {
        didSet {
            UserDefaults.standard.set(granularity, forKey: "granularity")
            rebuild()
        }
    }
    @Published private(set) var customNames: [String: String]
    @Published private(set) var customFolders: [CustomFolder]

    private(set) var records: [String: PhotoRecord] = [:]
    private var categoryByID: [String: PhotoCategory] = [:]
    private var groupByID: [String: PhotoGroup] = [:]
    private let store = IndexStore()
    private let lookStore = LookStore()
    private var looks: [String: LookVector] = [:]
    private var baseIndex: SearchIndex?
    private let analyzer = PhotoAnalyzer()
    private let matcher = NLSemanticMatcher()
    private var syncTask: Task<Void, Never>?
    private var rebuildTask: Task<Void, Never>?
    private var resyncWanted = false
    private var observer: LibraryObserver?
    private let log = Logger(subsystem: "com.stproperties.photofolders", category: "library")

    private init() {
        let g = UserDefaults.standard.double(forKey: "granularity")
        granularity = g == 0 ? 1.0 : g
        customNames = (UserDefaults.standard.dictionary(forKey: "customNames") as? [String: String]) ?? [:]
        if let data = UserDefaults.standard.data(forKey: "customFolders"),
           let list = try? JSONDecoder().decode([CustomFolder].self, from: data) {
            customFolders = list
        } else {
            customFolders = []
        }
    }

    // MARK: - Start

    func start() async {
        guard !loaded else { return }
        records = await store.load()
        looks = (await lookStore.load()).compactMapValues { LookVector(data: $0) }
        indexedPhotos = records.count
        loaded = true
        if !records.isEmpty { rebuild() }
        refreshAccess()
        if access == .full || access == .limited { begin() }
    }

    func requestAccess() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        refreshAccess()
        if access == .full || access == .limited { begin() }
    }

    private func refreshAccess() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: access = .full
        case .limited: access = .limited
        case .denied, .restricted: access = .denied
        default: access = .unknown
        }
    }

    private func begin() {
        if observer == nil {
            let o = LibraryObserver { [weak self] in Task { @MainActor in self?.sync() } }
            PHPhotoLibrary.shared().register(o)
            observer = o
        }
        sync()
    }

    // MARK: - Keeping the index current

    func sync() {
        guard access == .full || access == .limited else { return }
        if syncTask != nil { resyncWanted = true; return }
        syncTask = Task { [weak self] in
            await self?.runSync()
            guard let self else { return }
            self.syncTask = nil
            if self.resyncWanted { self.resyncWanted = false; self.sync() }
        }
    }

    func waitForSync() async {
        await syncTask?.value
    }

    func cancelSync() {
        syncTask?.cancel()
    }

    private func runSync() async {
        let assets = await Task.detached(priority: .userInitiated) { () -> [PHAsset] in
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
            let result = PHAsset.fetchAssets(with: .image, options: options)
            var list: [PHAsset] = []
            list.reserveCapacity(result.count)
            result.enumerateObjects { a, _, _ in list.append(a) }
            return list
        }.value

        var map: [String: PHAsset] = [:]
        for a in assets { map[a.localIdentifier] = a }
        ThumbnailCache.shared.register(map)
        totalPhotos = map.count

        // Forget deleted photos; refresh the cheap "favorite" mark.
        let removed = records.keys.filter { map[$0] == nil }
        var touched: [PhotoRecord] = []
        for id in removed { records[id] = nil; looks[id] = nil }
        for (id, a) in map {
            guard var r = records[id] else { continue }
            let fav = r.traits.contains(Trait.favorite)
            if fav != a.isFavorite {
                if a.isFavorite { r.traits.append(Trait.favorite) } else { r.traits.removeAll { $0 == Trait.favorite } }
                records[id] = r
                touched.append(r)
            }
        }
        if !removed.isEmpty { await store.remove(removed); await lookStore.remove(removed) }
        if !touched.isEmpty { await store.upsert(touched) }

        let todo = assets.filter { records[$0.localIdentifier]?.version != PhotoAnalyzer.version }
        indexedPhotos = records.count
        guard !todo.isEmpty else {
            if !removed.isEmpty || !touched.isEmpty || categories.isEmpty { rebuild() }
            await store.save()
            await lookStore.save()
            return
        }

        log.notice("sorting \(todo.count, privacy: .public) new photos of \(map.count, privacy: .public)")
        progressTotal = todo.count
        progressDone = 0
        isIndexing = true
        UIApplication.shared.isIdleTimerDisabled = true
        if records.isEmpty == false { rebuild() }

        let analyzer = self.analyzer
        var nextRebuild = min(40, todo.count)
        for chunk in todo.chunked(6) {
            if Task.isCancelled { break }
            let results = await withTaskGroup(of: PhotoAnalyzer.Analysis.self) { group -> [PhotoAnalyzer.Analysis] in
                for a in chunk { group.addTask { await analyzer.analyze(a) } }
                var out: [PhotoAnalyzer.Analysis] = []
                for await r in group { out.append(r) }
                return out
            }
            var newLooks: [String: Data] = [:]
            for r in results {
                records[r.record.id] = r.record
                if let look = r.look { looks[r.record.id] = look; newLooks[r.record.id] = look.data }
            }
            await store.upsert(results.map(\.record))
            await lookStore.upsert(newLooks)
            progressDone += chunk.count
            indexedPhotos = records.count
            log.notice("progress \(self.progressDone, privacy: .public) of \(self.progressTotal, privacy: .public)")
            if progressDone >= nextRebuild {
                rebuild()
                await store.save()
                await lookStore.save()
                nextRebuild = progressDone + min(max(progressDone, 40), 1500)
            }
        }
        await store.save()
        await lookStore.save()
        isIndexing = false
        UIApplication.shared.isIdleTimerDisabled = false
        rebuild()
        log.notice("sorting finished: \(self.records.count, privacy: .public) photos")
    }

    // MARK: - Folders and search

    func rebuild() {
        let recs = Array(records.values)
        let options = CategoryEngine.Options(granularity: granularity, customNames: customNames)
        let matcher = self.matcher
        let looks = self.looks
        let folders = self.customFolders
        rebuildTask?.cancel()
        isBuilding = true
        rebuildTask = Task { [weak self] in
            let all = await Task.detached(priority: .userInitiated) {
                CategoryEngine.buildAll(records: recs, looks: looks, customFolders: folders, options: options, matcher: matcher)
            }.value
            guard let self, !Task.isCancelled else { return }
            let built = (all.categories, all.index)
            self.categories = built.0
            self.searchIndex = built.1
            self.baseIndex = all.baseIndex
            var cmap: [String: PhotoCategory] = [:]
            var gmap: [String: PhotoGroup] = [:]
            for c in built.0 {
                cmap[c.id] = c
                for g in c.groups { gmap[g.id] = g }
            }
            self.categoryByID = cmap
            self.groupByID = gmap
            self.isBuilding = false
            let summary = built.0.map { "\($0.name)=\($0.photoIDs.count)" }.joined(separator: ", ")
            self.log.notice("folders: \(built.0.count, privacy: .public) — \(summary, privacy: .public)")
        }
    }

    func category(_ id: String) -> PhotoCategory? { categoryByID[id] }
    func group(_ id: String) -> PhotoGroup? { groupByID[id] }
    func record(_ id: String) -> PhotoRecord? { records[id] }

    func rename(_ categoryID: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { customNames[categoryID] = nil } else { customNames[categoryID] = trimmed }
        UserDefaults.standard.set(customNames, forKey: "customNames")
        rebuild()
    }

    // MARK: - The person's own folders

    func saveCustomFolder(_ folder: CustomFolder) {
        var f = folder
        f.name = f.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = customFolders.firstIndex(where: { $0.id == f.id }) { customFolders[i] = f } else { customFolders.append(f) }
        persistCustomFolders()
        rebuild()
    }

    func deleteCustomFolder(_ id: String) {
        customFolders.removeAll { $0.id == id }
        persistCustomFolders()
        rebuild()
    }

    func customFolder(forCategory categoryID: String) -> CustomFolder? {
        customFolders.first { $0.categoryID == categoryID }
    }

    /// Which photos a folder being edited would hold, right now.
    func preview(_ folder: CustomFolder) async -> CustomFolderResolver.Result {
        let recs = Array(records.values)
        let looks = self.looks
        let index = baseIndex ?? searchIndex
        return await Task.detached(priority: .userInitiated) {
            CustomFolderResolver.resolve(folder, records: recs, search: index, looks: looks)
        }.value
    }

    private func persistCustomFolders() {
        if let data = try? JSONEncoder().encode(customFolders) { UserDefaults.standard.set(data, forKey: "customFolders") }
    }

    func reanalyzeEverything() {
        syncTask?.cancel()
        Task {
            await syncTask?.value
            records = [:]
            looks = [:]
            await store.clear()
            await store.save()
            await lookStore.clear()
            await lookStore.save()
            categories = []
            searchIndex = nil
            sync()
        }
    }

    // MARK: - Background

    func scheduleBackgroundSorting() {
        guard isIndexing || totalPhotos > records.count else { return }
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskID)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        do { try BGTaskScheduler.shared.submit(request) } catch {
            log.info("background sorting not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }

    func runBackgroundTask(_ task: BGProcessingTask) {
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.cancelSync() }
        }
        Task {
            await start()
            sync()
            await waitForSync()
            task.setTaskCompleted(success: true)
            scheduleBackgroundSorting()
        }
    }
}

/// Tells the model when photos are added, removed or changed.
final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: () -> Void
    private var pending: DispatchWorkItem?

    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            self.pending?.cancel()
            let item = DispatchWorkItem { self.onChange() }
            self.pending = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
        }
    }
}
