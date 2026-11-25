import Foundation
import os

/// Only callers' fixed event names, numeric counters and known app enums are logged.
/// Never pass notification text, accessibility descriptions or titles here.
final class Diagnostics {
    static let shared = Diagnostics()
    private let queue = DispatchQueue(label: "AlienPing.diagnostics")
    private let system = Logger(subsystem: "local.alienping.mac", category: "notifications")
    let directory: URL
    var logURL: URL { directory.appendingPathComponent("AlienPing-diagnostics.jsonl") }
    var stateURL: URL { directory.appendingPathComponent("AlienPing-status.json") }
    init() {
        directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Psst",isDirectory:true)
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    }
    func event(_ event: String, _ fields: [String: Any] = [:]) {
        queue.async {
            var entry = fields
            entry["event"] = event
            entry["time"] = ISO8601DateFormatter().string(from: Date())
            entry["pid"] = ProcessInfo.processInfo.processIdentifier
            guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]), var line = String(data: data, encoding: .utf8) else { return }
            self.system.info("\(line, privacy: .public)")
            line += "\n"
            do {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: self.logURL.path), let size = attributes[.size] as? NSNumber, size.intValue > 262144 {
                    let backup = self.logURL.appendingPathExtension("1")
                    if FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.removeItem(at: backup) }
                    try FileManager.default.moveItem(at: self.logURL, to: backup)
                }
                if !FileManager.default.fileExists(atPath: self.logURL.path) {
                    FileManager.default.createFile(atPath: self.logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
                }
                let file = try FileHandle(forWritingTo: self.logURL)
                defer { try? file.close() }
                try file.seekToEnd(); try file.write(contentsOf: Data(line.utf8))
            } catch { self.system.error("Diagnostic file write failed") }
        }
    }
    func state(_ fields: [String: Any]) {
        queue.async {
            var state = fields
            state["updatedAt"] = ISO8601DateFormatter().string(from: Date())
            state["pid"] = ProcessInfo.processInfo.processIdentifier
            if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: self.stateURL, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.stateURL.path)
            }
        }
    }
}
