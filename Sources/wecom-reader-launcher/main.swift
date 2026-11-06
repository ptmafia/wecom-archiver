import ApplicationServices
import Foundation

// The system ties Accessibility permission to one exact file, and there is no developer certificate here.
// This small file never changes and owns the permission; the reader runs as its child, so rebuilding the reader needs no new grant.
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
_ = AXIsProcessTrustedWithOptions(options)

let reader = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("wecom-reader")
let process = Process()
process.executableURL = reader
process.arguments = ["daemon"]
do {
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
} catch {
    FileHandle.standardError.write(Data("cannot start reader: \(error)\n".utf8))
    exit(1)
}
