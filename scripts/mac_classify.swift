// Runs Apple's built-in Vision scene classifier and face finder on real Mac hardware over a folder of
// photos, printing JSON keyed by file name. The iOS simulator's classifier is a stand-in that returns
// the same answer for every picture, so simulator walks use these real results instead.
import AppKit
import Foundation
import Vision

struct Hit: Codable { let name: String; let confidence: Float }
struct Entry: Codable { let labels: [Hit]; let faces: Int; let look: String? }

let dir = CommandLine.arguments[1]
var out: [String: Entry] = [:]
let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
for f in files.sorted() where f.lowercased().hasSuffix(".jpg") {
    let path = (dir as NSString).appendingPathComponent(f)
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    let classify = VNClassifyImageRequest()
    let faces = VNDetectFaceRectanglesRequest()
    let looks = VNGenerateImageFeaturePrintRequest()
    try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([classify, faces, looks])
    var look: String?
    if let fp = looks.results?.first {
        let floats: [Float] = fp.elementType == .double
            ? fp.data.withUnsafeBytes { $0.bindMemory(to: Double.self).map { Float($0) } }
            : fp.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let maxAbs = floats.reduce(Float(0)) { max($0, abs($1)) }
        if maxAbs > 0 {
            let bytes = floats.map { UInt8(bitPattern: Int8(max(-127, min(127, ($0 / maxAbs * 127).rounded())))) }
            look = Data(bytes).base64EncodedString()
        }
    }
    let labels = (classify.results ?? []).filter { $0.confidence >= 0.1 }.prefix(20)
        .map { Hit(name: $0.identifier.replacingOccurrences(of: "_", with: " ").lowercased(), confidence: $0.confidence) }
    out[f] = Entry(labels: Array(labels), faces: faces.results?.count ?? 0, look: look)
    FileHandle.standardError.write("\(f): \(labels.prefix(4).map(\.name).joined(separator: ", "))\n".data(using: .utf8)!)
}
let enc = JSONEncoder()
enc.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try! enc.encode(out))
