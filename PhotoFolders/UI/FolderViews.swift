import SwiftUI

struct CategoryView: View {
    let categoryID: String
    @EnvironmentObject private var library: LibraryModel
    @State private var renaming: PhotoCategory?
    @State private var editing: EditTarget?
    @EnvironmentObject private var router: Router
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        Group {
            if let c = library.category(categoryID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let f = library.customFolder(forCategory: c.id) {
                            FlowLayout(spacing: 6) {
                                if !f.describe.isEmpty { Chip(text: "“\(f.describe)”", systemImage: "text.magnifyingglass") }
                                if !f.exampleIDs.isEmpty {
                                    Chip(text: f.exampleIDs.count == 1 ? "1 example photo" : "\(f.exampleIDs.count) example photos", systemImage: "photo.on.rectangle")
                                }
                                if !f.excluded.isEmpty { Chip(text: "\(f.excluded.count) left out", systemImage: "minus.circle", muted: true) }
                            }
                        }
                        if !c.keywords.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("What’s in here").font(.caption).foregroundStyle(.secondary)
                                FlowLayout(spacing: 6) {
                                    ForEach(c.keywords, id: \.self) { Chip(text: TextTools.title($0)) }
                                }
                            }
                        }
                        NavigationLink(value: Route.all(c.id)) {
                            HStack {
                                Label("All \(photoCount(c.photoIDs.count))", systemImage: "square.grid.3x3.fill")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Text(c.groups.count == 1 ? "1 group" : "\(c.groups.count) groups")
                            .font(.headline)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                            ForEach(c.groups) { g in
                                NavigationLink(value: Route.group(g.id)) {
                                    FolderTile(title: g.title, subtitle: g.subtitle, coverIDs: g.coverIDs, symbol: c.symbol)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { router.path.append(Route.group(g.id)) } label: { Label("Open", systemImage: "folder") }
                                } preview: {
                                    FolderPeek(title: g.title, subtitle: g.subtitle, ids: g.photoIDs)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
                .navigationTitle(c.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if let f = library.customFolder(forCategory: c.id) {
                                Button { editing = EditTarget(folder: f) } label: { Label("Edit folder", systemImage: "slider.horizontal.3") }
                            } else {
                                Button { renaming = c } label: { Label("Rename folder", systemImage: "pencil") }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Folder options")
                    }
                }
                .renameFolder($renaming)
                .sheet(item: $editing) { target in
                    CustomFolderEditor(folder: target.folder).environmentObject(library)
                }
            } else {
                ContentUnavailableView("This folder was re-sorted", systemImage: "folder.badge.questionmark",
                                       description: Text("New photos changed the folders. Go back to see them."))
            }
        }
    }
}

struct GroupPhotosView: View {
    let groupID: String
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        if let g = library.group(groupID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(g.subtitle).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
                    PhotoGridView(ids: g.photoIDs)
                }
            }
            .navigationTitle(g.title)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("This group was re-sorted", systemImage: "folder.badge.questionmark",
                                   description: Text("Go back to see the new groups."))
        }
    }
}

struct AllPhotosView: View {
    let categoryID: String
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        if let c = library.category(categoryID) {
            ScrollView { PhotoGridView(ids: c.photoIDs) }
                .navigationTitle(c.name)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("This folder was re-sorted", systemImage: "folder.badge.questionmark")
        }
    }
}
