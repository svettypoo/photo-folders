import Foundation

/// One thing the on-device vision model saw in a photo ("dog", "beach", "christmas tree").
struct LabelHit: Codable, Hashable {
    var name: String
    var confidence: Float
}

/// Everything the app learned about one photo. Stored on the phone only.
struct PhotoRecord: Codable, Identifiable, Hashable {
    var id: String            // PHAsset.localIdentifier
    var date: Date?
    var labels: [LabelHit]    // strongest first
    var text: String          // words read inside the photo (receipts, signs, screenshots)
    var traits: [String]      // screenshot, favorite, people, panorama, ...
    var faceCount: Int
    var latitude: Double?
    var longitude: Double?
    var version: Int

    var isScreenshot: Bool { traits.contains(Trait.screenshot) }
}

enum Trait {
    static let screenshot = "screenshot"
    static let favorite = "favorite"
    static let people = "people"
    static let groupPhoto = "group photo"
    static let panorama = "panorama"
    static let portraitMode = "portrait mode"
    static let livePhoto = "live photo"
    static let hdr = "hdr"
    static let text = "text"
}

struct PhotoGroup: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var photoIDs: [String]
    var coverIDs: [String]
}

struct PhotoCategory: Identifiable, Hashable {
    enum Kind: String, Hashable { case custom, invented, screenshots, unsorted }

    var id: String
    var name: String
    var keywords: [String]
    var symbol: String
    var kind: Kind
    var photoIDs: [String]    // newest first
    var coverIDs: [String]    // the photos that best represent the folder
    var groups: [PhotoGroup]
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
