import SwiftUI

struct SearchResultsView: View {
    let query: String
    @EnvironmentObject private var library: LibraryModel
    @State private var outcome = SearchOutcome()
    @State private var ranFor: String?

    private var full: [String] { outcome.hits.filter(\.matchedAll).map(\.id) }
    private var partial: [String] { Array(outcome.hits.filter { !$0.matchedAll }.prefix(300).map(\.id)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                understanding
                let folders = outcome.categoryIDs.compactMap { library.category($0) }
                if !folders.isEmpty {
                    Text("Folders").font(.headline).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(folders) { c in
                                NavigationLink(value: Route.category(c.id)) {
                                    FolderTile(title: c.name, subtitle: photoCount(c.photoIDs.count), coverIDs: c.coverIDs, symbol: c.symbol)
                                        .frame(width: 128)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                if ranFor != nil {
                    if outcome.hits.isEmpty && !outcome.isEmptyQuery {
                        ContentUnavailableView.search(text: query)
                    } else if !outcome.isEmptyQuery {
                        if !full.isEmpty {
                            Text(photoCount(full.count)).font(.headline).padding(.horizontal)
                            PhotoGridView(ids: full)
                        }
                        if !partial.isEmpty {
                            Text(full.isEmpty ? "Closest matches" : "Partly matching")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            PhotoGridView(ids: partial)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                }
                if library.isIndexing {
                    Text("Still sorting — more results will appear.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.immediately)
        .task(id: "\(query)|\(library.searchIndex?.photoCount ?? -1)|\(library.categories.count)") {
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled, let index = library.searchIndex else { return }
            let q = query
            let result = await Task.detached(priority: .userInitiated) { index.search(q) }.value
            guard !Task.isCancelled else { return }
            outcome = result
            ranFor = q
        }
    }

    @ViewBuilder private var understanding: some View {
        if !outcome.understood.isEmpty || outcome.dateLabel != nil {
            FlowLayout(spacing: 6) {
                ForEach(Array(outcome.understood.enumerated()), id: \.offset) { _, u in
                    if u.meanings.isEmpty {
                        Chip(text: u.term, systemImage: "text.magnifyingglass", muted: true)
                    } else if u.meanings.first == u.term {
                        Chip(text: TextTools.title(u.term), systemImage: "eye")
                    } else {
                        Chip(text: "\(u.term) → \(u.meanings.prefix(2).joined(separator: ", "))", systemImage: "eye")
                    }
                }
                if let d = outcome.dateLabel {
                    Chip(text: d, systemImage: "calendar", tint: .orange)
                }
            }
            .padding(.horizontal)
        }
    }
}
