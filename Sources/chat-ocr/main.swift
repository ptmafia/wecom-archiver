import Foundation
import ImageIO
import Vision

// Reads the words in pictures for tools/wechat_ocr.py, with macOS's own text recognition. Nothing leaves this Mac.
// One JSON object per line in: {"path": "...", "min_side": 300}. One per line out, in the same order:
// {"w": 1080, "h": 1920, "text": "..."}; "small": true instead of "text" when the shorter side is under min_side
// (a thumbnail: too small to read, and reading it only invents words); or "error" when it can't be read.

// The lowest CPU and disk priority there is: it runs while someone works on this Mac and must never be felt.
setpriority(PRIO_DARWIN_PROCESS, 0, PRIO_DARWIN_BG)

func read(_ url: URL, minSide: Int) -> [String: Any] {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return ["error": "unreadable"] }
    var out: [String: Any] = ["w": cg.width, "h": cg.height]
    if min(cg.width, cg.height) < minSide {
        out["small"] = true
        return out
    }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.recognitionLanguages = ["zh-Hans", "zh-Hant", "ja-JP", "en-US"]
    req.usesLanguageCorrection = true
    do {
        try VNImageRequestHandler(cgImage: cg).perform([req])
    } catch {
        out["error"] = "recognition"
        return out
    }
    let lines = (req.results ?? []).filter { ($0.topCandidates(1).first?.confidence ?? 0) >= 0.3 }
        .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        .compactMap { $0.topCandidates(1).first?.string }
    out["text"] = lines.joined(separator: "\n")
    return out
}

while let line = readLine() {
    var reply: [String: Any] = ["error": "bad request"]
    if let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let path = j["path"] as? String {
        let minSide = j["min_side"] as? Int ?? 0
        reply = autoreleasepool { read(URL(fileURLWithPath: path), minSide: minSide) }
    }
    let data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data(#"{"error":"encode"}"#.utf8)
    // Straight to the descriptor, one line per picture: the caller waits for each answer.
    FileHandle.standardOutput.write(data + Data([0x0A]))
}
