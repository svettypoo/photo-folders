import CoreML
import Foundation
import os
import Photos
import UIKit
import Vision

/// Looks at one photo with the models built into iOS (Vision scene classifier, face finder, text reader).
/// Nothing is downloaded and nothing leaves the phone.
final class PhotoAnalyzer {
    /// Bump when the analysis changes so old photos are looked at again.
    static let version = 2

    struct Analysis {
        var record: PhotoRecord
        var look: LookVector?
    }
    private let log = Logger(subsystem: "com.stproperties.photofolders", category: "analyzer")

    /// Vision and image loading are blocking calls: they run on this queue, never on the main thread
    /// or the Swift concurrency pool.
    private static let queue = DispatchQueue(label: "com.stproperties.photofolders.analyzer",
                                             qos: .userInitiated, attributes: .concurrent)
    private static let gate = DispatchSemaphore(value: 3)

    func analyze(_ asset: PHAsset) async -> Analysis {
        await withCheckedContinuation { (cont: CheckedContinuation<Analysis, Never>) in
            Self.queue.async {
                Self.gate.wait()
                defer { Self.gate.signal() }
                let started = Date()
                let result = self.analyzeNow(asset)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                let top = result.record.labels.prefix(3).map(\.name).joined(separator: ", ")
                self.log.notice("analyzed in \(ms, privacy: .public) ms: \(top, privacy: .public)")
                cont.resume(returning: result)
            }
        }
    }

    /// Blocking. Call only from the analyzer queue.
    private func analyzeNow(_ asset: PHAsset) -> Analysis {
        var traits: [String] = []
        let subtypes = asset.mediaSubtypes
        if subtypes.contains(.photoScreenshot) { traits.append(Trait.screenshot) }
        if subtypes.contains(.photoPanorama) { traits.append(Trait.panorama) }
        if subtypes.contains(.photoLive) { traits.append(Trait.livePhoto) }
        if subtypes.contains(.photoDepthEffect) { traits.append(Trait.portraitMode) }
        if subtypes.contains(.photoHDR) { traits.append(Trait.hdr) }
        if asset.isFavorite { traits.append(Trait.favorite) }

        var record = PhotoRecord(
            id: asset.localIdentifier, date: asset.creationDate, labels: [], text: "", traits: traits,
            faceCount: 0, latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude, version: Self.version)

        guard let image = Self.loadImageNow(asset, side: 1024), let cg = image.cgImage else {
            log.info("no local image for \(asset.localIdentifier, privacy: .public)")
            return Analysis(record: record, look: nil)
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])

        let classify = VNClassifyImageRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let looks = VNGenerateImageFeaturePrintRequest()
        Self.preferCPUOnSimulator(classify)
        Self.preferCPUOnSimulator(faces)
        Self.preferCPUOnSimulator(looks)
        do {
            try handler.perform([classify, faces, looks])
        } catch {
            log.error("vision failed: \(error.localizedDescription, privacy: .public)")
        }
        let labels = (classify.results ?? [])
            .filter { $0.confidence >= 0.1 }
            .prefix(20)
            .map { LabelHit(name: TextTools.prettyLabel($0.identifier), confidence: $0.confidence) }
        record.labels = Array(labels)
        record.faceCount = faces.results?.count ?? 0
        var look = looks.results?.first.flatMap { LookVector.quantize(Self.floats($0)) }
        #if targetEnvironment(simulator)
        if let real = Self.simulatorLabels(for: asset) {
            record.labels = real.labels.map { LabelHit(name: $0.name, confidence: $0.confidence) }
            record.faceCount = real.faces
            if let b64 = real.look, let data = Data(base64Encoded: b64) { look = LookVector(data: data) }
        }
        #endif
        if record.faceCount > 0 { record.traits.append(Trait.people) }
        if record.faceCount >= 3 { record.traits.append(Trait.groupPhoto) }

        // Read words only where words are likely: keeps sorting fast.
        let wantsText = record.isScreenshot || record.labels.contains { l in
            l.confidence >= 0.2 && Vocabulary.textHints.contains { l.name.contains($0) }
        }
        if wantsText {
            let reader = VNRecognizeTextRequest()
            reader.recognitionLevel = .accurate
            reader.usesLanguageCorrection = true
            Self.preferCPUOnSimulator(reader)
            do {
                try handler.perform([reader])
                let lines = (reader.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                record.text = String(lines.joined(separator: " ").prefix(4000))
                if lines.count >= 3 { record.traits.append(Trait.text) }
            } catch {
                log.error("text reader failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return Analysis(record: record, look: look)
    }

    /// The numbers inside Apple's image feature print (what a photo looks like), as floats.
    static func floats(_ observation: VNFeaturePrintObservation) -> [Float] {
        let data = observation.data
        switch observation.elementType {
        case .float: return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        case .double: return data.withUnsafeBytes { $0.bindMemory(to: Double.self).map { Float($0) } }
        default: return []
        }
    }

    #if targetEnvironment(simulator)
    /// Simulator only: its scene classifier is a stand-in that gives every picture the same answer, so a
    /// test run may drop real results from Apple's classifier on a Mac into Documents/sim-labels.json.
    private struct SimEntry: Decodable { struct Hit: Decodable { let name: String; let confidence: Float }; let labels: [Hit]; let faces: Int; let look: String? }
    private static let simLabels: [String: SimEntry] = {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("sim-labels.json")
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: SimEntry].self, from: data)) ?? [:]
    }()
    private static func simulatorLabels(for asset: PHAsset) -> SimEntry? {
        guard !simLabels.isEmpty, let name = PHAssetResource.assetResources(for: asset).first?.originalFilename else { return nil }
        return simLabels[name] ?? simLabels[name.replacingOccurrences(of: ".jpeg", with: ".jpg")]
    }
    #endif

    /// The simulator has no neural engine; Vision needs to be told to use the CPU there.
    private static func preferCPUOnSimulator(_ request: VNRequest) {
        #if targetEnvironment(simulator)
        if let cpu = MLComputeDevice.allComputeDevices.first(where: {
            if case .cpu = $0 { return true } else { return false }
        }) {
            request.setComputeDevice(cpu, for: .main)
        }
        #endif
    }

    /// A local copy of the photo, loaded synchronously (allowed off the main thread). Never downloads from
    /// iCloud for analysis; falls back to the small local preview.
    static func loadImageNow(_ asset: PHAsset, side: CGFloat) -> UIImage? {
        if let img = requestNow(asset, side: side, mode: .highQualityFormat) { return img }
        return requestNow(asset, side: side, mode: .fastFormat)
    }

    private static func requestNow(_ asset: PHAsset, side: CGFloat, mode: PHImageRequestOptionsDeliveryMode) -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = mode
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true
        var result: UIImage?
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit, options: options
        ) { image, _ in
            result = image
        }
        return result
    }
}

/// Makes sure a continuation is resumed exactly once.
final class ResumeOnce {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
