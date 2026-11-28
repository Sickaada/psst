import Foundation

/// Banner subjects are usable only when exactly one known conversation owns the title.
public struct ChatRouteIndex {
    private var destinations: [SourceApp: [String: Set<UUID>]] = [:]
    public init() {}

    private func key(_ title: String) -> String {
        title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    public mutating func add(_ id: UUID, title: String, source: SourceApp) {
        let name = key(title)
        guard !name.isEmpty else { return }
        destinations[source, default: [:]][name, default: []].insert(id)
    }

    public func destination(for entry: InboxEntry) -> UUID? {
        let name = key(entry.title)
        let generic = ["notification", "new notification", "new chat", "untitled", "notification from " + entry.source.rawValue.lowercased(), entry.source.rawValue.lowercased()]
        guard !generic.contains(name), let ids = destinations[entry.source]?[name], ids.count == 1 else { return nil }
        return ids.first
    }

    public static func load(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
        struct CodexRow: Decodable { let id: UUID; let thread_name: String }
        struct ClaudeRow: Decodable { let sessionId: String; let title: String }
        var index = Self()
        let decoder = JSONDecoder()
        let codex = home.appendingPathComponent(".codex/session_index.jsonl")
        if let data = try? Data(contentsOf: codex) {
            for line in data.split(separator: 10) {
                if let row = try? decoder.decode(CodexRow.self, from: Data(line)) {
                    index.add(row.id, title: row.thread_name, source: .codex)
                }
            }
        }
        let root = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        let fm = FileManager.default
        func children(_ directory: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        }
        for account in children(root) where UUID(uuidString: account.lastPathComponent) != nil {
            for org in children(account) where UUID(uuidString: org.lastPathComponent) != nil {
                for file in children(org) where file.pathExtension == "json" {
                    let stem = file.deletingPathExtension().lastPathComponent
                    guard stem.hasPrefix("local_"), let id = UUID(uuidString: String(stem.dropFirst(6))),
                          let data = try? Data(contentsOf: file),
                          let row = try? decoder.decode(ClaudeRow.self, from: data), row.sessionId == stem else { continue }
                    index.add(id, title: row.title, source: .claude)
                }
            }
        }
        return index
    }
}
