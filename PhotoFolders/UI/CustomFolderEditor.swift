import PhotosUI
import SwiftUI

/// Make or change one of your own folders: name it, describe it, and/or show example photos.
/// The photos it will hold are previewed live; tap one to leave it out.
struct CustomFolderEditor: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomFolder
    @State private var picks: [PhotosPickerItem] = []
    @State private var preview = CustomFolderResolver.Result(candidates: [], members: [])
    @State private var computing = false
    @State private var confirmDelete = false
    private let isNew: Bool
    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 2)]

    init(folder: CustomFolder?) {
        _draft = State(initialValue: folder ?? CustomFolder())
        isNew = folder == nil
    }

    private var previewKey: String {
        "\(draft.describe)|\(draft.exampleIDs.joined(separator: ","))|\(draft.closeness)|\(draft.included.count)|\(library.indexedPhotos)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder name", text: $draft.name)
                        .accessibilityIdentifier("folderName")
                } header: {
                    Text("Name")
                }

                Section {
                    TextField("e.g. receipts, dogs at the beach, snow", text: $draft.describe, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("folderDescription")
                } header: {
                    Text("What goes in it")
                } footer: {
                    Text("Plain words, like the search bar. Leave empty if you’d rather show examples.")
                }

                Section {
                    if !draft.exampleIDs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(draft.exampleIDs, id: \.self) { id in
                                    AssetImageView(id: id, pixels: 200)
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                draft.exampleIDs.removeAll { $0 == id }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .black.opacity(0.6))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(3)
                                            .accessibilityLabel("Remove example")
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    PhotosPicker(selection: $picks, maxSelectionCount: 20, matching: .images, photoLibrary: .shared()) {
                        Label(draft.exampleIDs.isEmpty ? "Choose example photos" : "Add more examples",
                              systemImage: "photo.badge.plus")
                    }
                    if !draft.exampleIDs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("How alike").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $draft.closeness, in: 0...1) {
                                Text("How alike")
                            } minimumValueLabel: {
                                Text("Very").font(.caption)
                            } maximumValueLabel: {
                                Text("Loosely").font(.caption)
                            }
                        }
                    }
                } header: {
                    Text("Example photos")
                } footer: {
                    Text("Pick a few photos of what you mean — your cat, your car, a place. The app adds photos that look like them.")
                }

                Section {
                    if computing && preview.candidates.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if preview.candidates.isEmpty {
                        Text(draft.hasRule ? "No photos match yet." : "Describe it or pick examples to see which photos go in.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(preview.candidates.prefix(300), id: \.self) { id in
                                let out = draft.excluded.contains(id)
                                AssetImageView(id: id, pixels: 200)
                                    .aspectRatio(1, contentMode: .fit)
                                    .opacity(out ? 0.3 : 1)
                                    .overlay {
                                        if out {
                                            Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if out { draft.excluded.removeAll { $0 == id } } else { draft.excluded.append(id) }
                                    }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityLabel(out ? "Left out. Tap to put back." : "In the folder. Tap to leave out.")
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    }
                } header: {
                    let n = preview.candidates.filter { !draft.excluded.contains($0) }.count
                    Text(preview.candidates.isEmpty ? "Preview" : "Preview · \(photoCount(n))")
                } footer: {
                    if !preview.candidates.isEmpty {
                        Text("Tap a photo to leave it out. New photos that match are added on their own. These photos move out of the invented folders.")
                    }
                }

                if !isNew {
                    Section {
                        Button("Delete folder", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Only the folder goes away. Your photos stay in your library and return to the invented folders.")
                    }
                }
            }
            .navigationTitle(isNew ? "New folder" : "Edit folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        library.saveCustomFolder(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || !draft.hasRule)
                }
            }
            .confirmationDialog("Delete this folder?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete folder", role: .destructive) {
                    library.deleteCustomFolder(draft.id)
                    dismiss()
                }
            } message: {
                Text("Your photos are not deleted.")
            }
            .onChange(of: picks) { _, items in
                let ids = items.compactMap(\.itemIdentifier)
                for id in ids where !draft.exampleIDs.contains(id) { draft.exampleIDs.append(id) }
                if draft.name.trimmingCharacters(in: .whitespaces).isEmpty, !ids.isEmpty, draft.describe.isEmpty {
                    draft.name = "My photos"
                }
                if !items.isEmpty { picks = [] }
            }
            .task(id: previewKey) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                computing = true
                let result = await library.preview(draft)
                guard !Task.isCancelled else { return }
                preview = result
                computing = false
            }
        }
    }
}
