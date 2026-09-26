import SwiftUI
import UIKit

struct ViewerItem: Identifiable {
    let id = UUID()
    let ids: [String]
    let index: Int
}

struct PhotoViewer: View {
    let ids: [String]
    @State private var index: Int
    @State private var showInfo = false
    @State private var chrome = true
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryModel

    init(ids: [String], start: Int) {
        self.ids = ids
        _index = State(initialValue: start)
    }

    var body: some View {
        TabView(selection: $index) {
            ForEach(ids.indices, id: \.self) { i in
                ZoomablePhoto(id: ids[i], onTap: { withAnimation { chrome.toggle() } })
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if chrome {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).padding(10).background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                    Text("\(index + 1) of \(ids.count)")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Button { withAnimation { showInfo.toggle() } } label: {
                        Image(systemName: showInfo ? "info.circle.fill" : "info.circle")
                            .font(.headline).padding(10).background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("What the app saw")
                }
                .foregroundStyle(.white)
                .padding(.horizontal)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showInfo, chrome, ids.indices.contains(index), let r = library.record(ids[index]) {
                PhotoInfoCard(record: r).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusBarHidden(!chrome)
        .preferredColorScheme(.dark)
    }
}

struct ZoomablePhoto: View {
    let id: String
    var onTap: () -> Void = {}
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { v in scale = min(6, max(1, lastScale * v.magnification)) }
                            .onEnded { _ in
                                lastScale = scale
                                if scale <= 1.01 { reset() }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { v in
                                offset = CGSize(width: lastOffset.width + v.translation.width,
                                                height: lastOffset.height + v.translation.height)
                            }
                            .onEnded { _ in lastOffset = offset },
                        including: scale > 1 ? .all : .subviews
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.3)) {
                            if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                        }
                    }
                    .onTapGesture(count: 1) { onTap() }
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: id) {
            if let small = await ThumbnailCache.shared.image(for: id, pixels: 480, fill: false), image == nil {
                image = small
            }
            if let big = await ThumbnailCache.shared.image(for: id, pixels: 2400, fill: false) {
                image = big
            }
        }
    }

    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}

struct PhotoInfoCard: View {
    let record: PhotoRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let d = record.date {
                Text(d.formatted(date: .complete, time: .shortened)).font(.subheadline.weight(.semibold))
            }
            if !record.labels.isEmpty || !record.traits.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(record.traits, id: \.self) { Chip(text: TextTools.title($0), systemImage: "tag", tint: .orange) }
                    ForEach(record.labels.prefix(10), id: \.name) { l in
                        Chip(text: "\(TextTools.title(l.name)) \(Int((l.confidence * 100).rounded()))%")
                    }
                }
            }
            if !record.text.isEmpty {
                Text(record.text).font(.caption).lineLimit(4).foregroundStyle(.secondary)
            }
            Label("Seen by this iPhone only", systemImage: "lock.iphone").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding()
    }
}
