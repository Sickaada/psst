import Foundation

/// Stop events carry their conversation ID directly.
public struct CodexUpdate: Decodable {
    public let session_id: UUID
    public let turn_id: UUID
    public let hook_event_name: String
    public let last_assistant_message: String?

    public func entry(at date:Date = Date()) -> InboxEntry? {
        guard hook_event_name == "Stop" else { return nil }
        let message=(last_assistant_message ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        let lines=message.split(separator:"\n",maxSplits:1,omittingEmptySubsequences:true)
        let hasHeading=lines.count==2 && lines[0].count <= 100
        let title=hasHeading ? String(lines[0]).trimmingCharacters(in:CharacterSet(charactersIn:"#* ")) : "Codex replied"
        let body=hasHeading ? String(lines[1]).trimmingCharacters(in:.whitespacesAndNewlines) : message
        var entry=InboxEntry(id:turn_id,source:.codex,title:title,body:body,date:date)
        entry.chatID=session_id
        return entry
    }
}

public extension InboxEntry {
    var chatURL:URL? {
        guard let id = chatID?.uuidString.lowercased() else { return nil }
        switch source {
        case .codex: return URL(string: "codex://threads/" + id)
        case .claude: return URL(string: "claude://code/continue?session=local_" + id)
        default: return nil
        }
    }
    func earlierUpdates(in entries:[InboxEntry])->[InboxEntry] {
        guard let chatID else { return [] }
        return entries.filter { $0.source == source && $0.chatID == chatID && $0.id != id && $0.date <= date }
            .sorted { $0.date > $1.date }
    }
}
