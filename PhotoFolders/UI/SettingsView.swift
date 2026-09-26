import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRestart = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Your library") {
                    LabeledContent("Photos", value: library.totalPhotos.formatted())
                    LabeledContent("Looked at", value: library.indexedPhotos.formatted())
                    LabeledContent("Folders", value: library.categories.count.formatted())
                    if library.isIndexing {
                        ProgressView(value: Double(library.progressDone), total: Double(max(1, library.progressTotal))) {
                            Text("Sorting \(library.progressDone.formatted()) of \(library.progressTotal.formatted())")
                                .font(.caption)
                        }
                    }
                }
                Section {
                    Picker("Folders", selection: $library.granularity) {
                        Text("Fewer").tag(0.6)
                        Text("Balanced").tag(1.0)
                        Text("More").tag(1.6)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How many folders")
                } footer: {
                    Text("Folders are invented from what is in your photos. Fewer gives broad folders, More gives narrow ones.")
                }
                Section {
                    Button("Re-sort folders now") { library.rebuild() }
                    Button("Look at every photo again", role: .destructive) { confirmRestart = true }
                } footer: {
                    Text("New photos are sorted automatically when you open the app, and overnight while the phone charges.")
                }
                if library.access == .limited {
                    Section {
                        Button("Allow access to all photos") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    } footer: {
                        Text("Right now the app only sees the photos you picked.")
                    }
                }
                Section("Privacy") {
                    Label("Sorting, reading text in photos and search all run on this iPhone with Apple’s built-in models.", systemImage: "cpu")
                    Label("The app has no account, sends nothing to any AI company, and keeps its notes out of iCloud backups.", systemImage: "lock.shield")
                }
                .font(.callout)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Look at every photo again?", isPresented: $confirmRestart, titleVisibility: .visible) {
                Button("Start over", role: .destructive) { library.reanalyzeEverything() }
            } message: {
                Text("Your photos are not touched. The app forgets what it learned and sorts everything again, which can take a while.")
            }
        }
    }
}
