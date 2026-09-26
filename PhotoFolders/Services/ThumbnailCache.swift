import Photos
import UIKit

/// Loads and remembers small and large versions of photos for the screens.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let manager = PHCachingImageManager()
    private let images = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var assets: [String: PHAsset] = [:]

    init() {
        images.countLimit = 600
        manager.allowsCachingHighQualityImages = false
    }

    func register(_ list: [String: PHAsset]) {
        lock.lock(); assets = list; lock.unlock()
    }

    func asset(_ id: String) -> PHAsset? {
        lock.lock()
        if let a = assets[id] { lock.unlock(); return a }
        lock.unlock()
        guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        lock.lock(); assets[id] = a; lock.unlock()
        return a
    }

    /// `pixels` is the longest side wanted. Big images may come from the user's own iCloud Photos (Apple),
    /// never from any AI service.
    func image(for id: String, pixels: CGFloat, fill: Bool = true) async -> UIImage? {
        let bucket = pixels <= 200 ? 200 : pixels <= 480 ? 480 : pixels <= 900 ? 900 : 2400
        let key = "\(id)#\(bucket)" as NSString
        if let hit = images.object(forKey: key) { return hit }
        guard let asset = asset(id) else { return nil }
        let size = CGSize(width: bucket, height: bucket)
        let image: UIImage? = await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = bucket >= 900
            let once = ResumeOnce()
            manager.requestImage(for: asset, targetSize: size, contentMode: fill ? .aspectFill : .aspectFit,
                                 options: options) { img, _ in
                if once.claim() { cont.resume(returning: img) }
            }
        }
        if let image { images.setObject(image, forKey: key) }
        return image
    }
}
