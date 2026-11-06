import Foundation
import Vision
import WeComCore

/// Reads the text inside images WeCom has cached. Only runs after the conversations are done.
enum OCR {
    private static var profile: URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.tencent.WeWorkMac/Data/Documents/Profiles")
        guard let d = try? Data(contentsOf: base.appendingPathComponent("setting.json")),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let p = j["CurrentProfile"] as? String else { return nil }
        return base.appendingPathComponent(p)
    }
    private static var index: URL { archive.root.appendingPathComponent("images.jsonl") }

    static func profileReadable() -> Bool {
        guard let p = profile else { return false }
        return FileManager.default.isReadableFile(atPath: p.appendingPathComponent("Caches/Images").path)
    }
    static func count() -> Int { (try? String(contentsOf: index, encoding: .utf8))?.split(separator: "\n").count ?? 0 }

    private static func recognize(_ url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["zh-Hans", "zh-Hant", "ja-JP", "en-US"]
        req.usesLanguageCorrection = true
        guard (try? VNImageRequestHandler(cgImage: cg).perform([req])) != nil else { return nil }
        let lines = (req.results ?? []).filter { ($0.topCandidates(1).first?.confidence ?? 0) >= 0.3 }
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    static func run(stop: () -> Bool) {
        guard let p = profile else { return }
        let root = p.appendingPathComponent("Caches/Images")
        let fm = FileManager.default
        var done = Set<String>()
        if let s = try? String(contentsOf: index, encoding: .utf8) {
            let dec = JSONDecoder()
            for l in s.split(separator: "\n") { if let e = try? dec.decode([String: String].self, from: Data(l.utf8)), let f = e["file"] { done.insert(f) } }
        }
        let months = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted(by: >)
        var n = 0
        for m in months {
            let folders = ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(m).path)) ?? [])
                .filter { !$0.hasSuffix("_THUMB") && !$0.hasSuffix("_HD") }
            for f in folders {
                let id = "\(m)/\(f)"
                if done.contains(id) { continue }
                if stop() { log("images read this round: \(n)"); return }
                let dir = root.appendingPathComponent(m).appendingPathComponent(f)
                guard let name = try? fm.contentsOfDirectory(atPath: dir.path).first(where: { !$0.hasPrefix(".") }) else { continue }
                let file = dir.appendingPathComponent(name)
                let text = autoreleasepool { recognize(file) } ?? ""
                let mtime = (try? fm.attributesOfItem(atPath: file.path)[.modificationDate] as? Date).map { isoFormat.string(from: $0) } ?? ""
                let line = ["file": id, "name": name, "at": mtime, "text": text]
                if let d = try? JSONSerialization.data(withJSONObject: line, options: [.withoutEscapingSlashes]) {
                    var out = d; out.append(0x0A)
                    if let h = try? FileHandle(forWritingTo: index) { h.seekToEndOfFile(); h.write(out); try? h.close() }
                    else { fm.createFile(atPath: index.path, contents: out, attributes: [.posixPermissions: 0o600]) }
                }
                n += 1
            }
        }
        log("images read this round: \(n), finished")
    }
}
