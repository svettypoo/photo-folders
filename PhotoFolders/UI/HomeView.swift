import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        switch library.access {
        case .full, .limited:
            HomeView()
        case .denied:
            OnboardingView(denied: true)
        case .unknown:
            if library.loaded { OnboardingView(denied: false) } else { ProgressView() }
        }
    }
}

struct OnboardingView: View {
    let denied: Bool
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "folder.fill.badge.gearshape")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 10) {
                Text("Your photos, sorted into folders")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("Photo Folders looks at your pictures, invents folders for what it finds, and lets you search them in plain words.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                Label("Folders invented from your own photos", systemImage: "sparkles.rectangle.stack")
                Label("Search like “dog at the beach last summer”", systemImage: "magnifyingglass")
                Label("Everything happens on this iPhone. Nothing is uploaded.", systemImage: "lock.iphone")
            }
            .font(.callout)
            Spacer()
            if denied {
                Text("Photo access is turned off.").foregroundStyle(.secondary)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("Open Settings").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    Task { await library.requestAccess() }
                } label: {
                    Text("Allow Photo Access").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(28)
    }
}

struct HomeView: View {
    @EnvironmentObject private var library: LibraryModel
    @State private var query = ""
    @StateObject private var router = Router()
    @State private var showSettings = false
    @State private var renaming: PhotoCategory?
    @State private var launchArgsApplied = false
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack(path: $router.path) {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    folders
                } else {
                    SearchResultsView(query: query)
                }
            }
            .navigationTitle("Photo Folders")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Try “dog on the beach last summer”")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .category(let id): CategoryView(categoryID: id)
                case .group(let id): GroupPhotosView(groupID: id)
                case .all(let id): AllPhotosView(categoryID: id)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(library)
            }
            .renameFolder($renaming)
        }
        .environmentObject(router)
        .onAppear(perform: applyLaunchArguments)
        .onChange(of: library.categories) { _, _ in applyLaunchArguments() }
    }

    private var folders: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatusBanner()
                if library.categories.isEmpty {
                    if library.isIndexing || library.isBuilding {
                        ProgressView("Inventing folders…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if library.totalPhotos == 0 && library.loaded {
                        ContentUnavailableView("No photos yet", systemImage: "photo.on.rectangle",
                                               description: Text("Take or add some photos and they will be sorted here."))
                    }
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    ForEach(library.categories) { c in
                        NavigationLink(value: Route.category(c.id)) {
                            FolderTile(title: c.name, subtitle: photoCount(c.photoIDs.count), coverIDs: c.coverIDs, symbol: c.symbol)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { router.path.append(Route.category(c.id)) } label: { Label("Open", systemImage: "folder") }
                            Button { router.path.append(Route.all(c.id)) } label: { Label("All photos", systemImage: "square.grid.3x3") }
                            Button { renaming = c } label: { Label("Rename", systemImage: "pencil") }
                        } preview: {
                            FolderPeek(title: c.name, subtitle: peekSubtitle(c), ids: c.photoIDs)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .refreshable { library.sync() }
    }

    private func peekSubtitle(_ c: PhotoCategory) -> String {
        let groups = c.groups.count == 1 ? "1 group" : "\(c.groups.count) groups"
        return "\(photoCount(c.photoIDs.count)) · \(groups)"
    }

    /// Lets automated screenshots open a screen directly: -PFQuery "dog", -PFOpen first|group, -PFSettings YES
    private func applyLaunchArguments() {
        guard !launchArgsApplied else { return }
        let d = UserDefaults.standard
        if let q = d.string(forKey: "PFQuery"), !q.isEmpty { query = q; launchArgsApplied = true; return }
        if d.bool(forKey: "PFSettings") { showSettings = true; launchArgsApplied = true; return }
        guard let open = d.string(forKey: "PFOpen"), let first = library.categories.first else {
            return
        }
        launchArgsApplied = true
        router.path.append(Route.category(first.id))
        if open == "group", let g = first.groups.first { router.path.append(Route.group(g.id)) }
    }
}

struct StatusBanner: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if library.isIndexing {
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sorting your photos on this iPhone")
                            .font(.subheadline.weight(.semibold))
                        Text("\(library.progressDone.formatted()) of \(library.progressTotal.formatted()) looked at · folders fill in as it goes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: Double(library.progressDone), total: Double(max(1, library.progressTotal)))
            } else if !library.categories.isEmpty {
                Label("\(photoCount(library.indexedPhotos)) in \(library.categories.count == 1 ? "1 folder" : "\(library.categories.count) folders") · sorted on this iPhone",
                      systemImage: "lock.iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if library.access == .limited {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("Only some photos are shared with the app. Tap to allow all.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                }
            }
        }
        .padding(library.isIndexing ? 14 : 0)
        .background(library.isIndexing ? AnyShapeStyle(Material.thinMaterial) : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

final class Router: ObservableObject {
    @Published var path = NavigationPath()
}
