import SwiftUI
import UIKit

enum Route: Hashable {
    case category(String)
    case group(String)
    case all(String)
}

func photoCount(_ n: Int) -> String {
    n == 1 ? "1 photo" : "\(n.formatted()) photos"
}

/// One photo from the library, filling whatever frame it is given.
struct AssetImageView: View {
    let id: String
    var pixels: CGFloat = 300
    @State private var image: UIImage?
    @State private var loadedID: String?

    var body: some View {
        Color(.secondarySystemFill)
            .overlay {
                if let image, loadedID == id {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: id) {
                let img = await ThumbnailCache.shared.image(for: id, pixels: pixels)
                withAnimation(.easeOut(duration: 0.15)) {
                    image = img
                    loadedID = id
                }
            }
    }
}

/// 1–4 photos arranged as the face of a folder.
struct MosaicView: View {
    let ids: [String]
    let symbol: String

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let gap: CGFloat = 2
            let px = w * UIScreen.main.scale
            switch ids.count {
            case 0:
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
                }
            case 1:
                AssetImageView(id: ids[0], pixels: px)
            case 2:
                HStack(spacing: gap) {
                    AssetImageView(id: ids[0], pixels: px / 2)
                    AssetImageView(id: ids[1], pixels: px / 2)
                }
            case 3:
                HStack(spacing: gap) {
                    AssetImageView(id: ids[0], pixels: px * 0.6)
                        .frame(width: (w - gap) * 0.6)
                    VStack(spacing: gap) {
                        AssetImageView(id: ids[1], pixels: px / 2)
                        AssetImageView(id: ids[2], pixels: px / 2)
                    }
                }
            default:
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        AssetImageView(id: ids[0], pixels: px / 2)
                        AssetImageView(id: ids[1], pixels: px / 2)
                    }
                    HStack(spacing: gap) {
                        AssetImageView(id: ids[2], pixels: px / 2)
                        AssetImageView(id: ids[3], pixels: px / 2)
                    }
                }
            }
        }
    }
}

struct FolderBackShape: Shape {
    func path(in r: CGRect) -> Path {
        let tabH: CGFloat = 14
        let radius: CGFloat = 16
        var p = Path()
        p.addRoundedRect(in: CGRect(x: r.minX, y: r.minY + tabH, width: r.width, height: r.height - tabH),
                         cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        p.addRoundedRect(in: CGRect(x: r.minX, y: r.minY, width: r.width * 0.42, height: tabH + radius),
                         cornerSize: CGSize(width: 9, height: 9), style: .continuous)
        return p
    }
}

/// A folder with a live preview of the photos inside.
struct FolderTile: View {
    let title: String
    let subtitle: String
    let coverIDs: [String]
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .top) {
                FolderBackShape()
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.3)],
                                         startPoint: .top, endPoint: .bottom))
                MosaicView(ids: coverIDs, symbol: symbol)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .padding(.horizontal, 7)
                    .padding(.top, 21)
                    .padding(.bottom, 7)
            }
            .aspectRatio(1.05, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(7)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(13)
            }
            .shadow(color: .black.opacity(0.10), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityHint("Opens the folder. Touch and hold to preview.")
    }
}

/// What you see when you touch and hold a folder: a bigger look inside before opening it.
struct FolderPeek: View {
    let title: String
    let subtitle: String
    let ids: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                ForEach(Array(ids.prefix(9)), id: \.self) { id in
                    AssetImageView(id: id, pixels: 320)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
        .padding(14)
        .frame(width: 330)
        .background(Color(.systemBackground))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .accentColor
    var muted = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.caption2) }
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(muted ? Color.secondary : tint)
        .background((muted ? Color.secondary : tint).opacity(0.12), in: Capsule())
    }
}

/// Square photo grid; tapping a photo opens it full screen.
struct PhotoGridView: View {
    let ids: [String]
    @State private var viewer: ViewerItem?
    @EnvironmentObject private var library: LibraryModel
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 2)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                AssetImageView(id: id, pixels: 300)
                    .aspectRatio(1, contentMode: .fit)
                    .contentShape(Rectangle())
                    .onTapGesture { viewer = ViewerItem(ids: ids, index: i) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(library.record(id)?.labels.prefix(3).map(\.name).joined(separator: ", ") ?? "Photo")
            }
        }
        .fullScreenCover(item: $viewer) { item in
            PhotoViewer(ids: item.ids, start: item.index).environmentObject(library)
        }
    }
}

/// A named rename box used by folders.
struct RenameModifier: ViewModifier {
    @Binding var target: PhotoCategory?
    @State private var text = ""
    @EnvironmentObject private var library: LibraryModel

    func body(content: Content) -> some View {
        content
            .alert("Rename folder", isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })) {
                TextField("Folder name", text: $text)
                Button("Save") {
                    if let t = target { library.rename(t.id, to: text) }
                    target = nil
                }
                Button("Use the invented name") {
                    if let t = target { library.rename(t.id, to: "") }
                    target = nil
                }
                Button("Cancel", role: .cancel) { target = nil }
            } message: {
                Text("Leave empty to go back to the name the app invented.")
            }
            .onChange(of: target) { _, t in text = t?.name ?? "" }
    }
}

extension View {
    func renameFolder(_ target: Binding<PhotoCategory?>) -> some View { modifier(RenameModifier(target: target)) }
}
