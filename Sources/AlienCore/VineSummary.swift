import Foundation

public enum VineSummary {
    public static func previewable(_ entries:[InboxEntry])->[InboxEntry] {
        entries.filter {
            !$0.read && ($0.source == .claude || $0.source == .codex) &&
            (!$0.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !$0.body.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }.sorted{$0.date>$1.date}
    }
    public static func timeline(_ entries:[InboxEntry])->[InboxEntry] {
        var counts:[SourceApp:Int]=[:]
        let visible=previewable(entries).filter { entry in
            guard counts[entry.source,default:0] < 2 else { return false }
            counts[entry.source,default:0] += 1
            return true
        }
        return Array(visible.reversed())
    }
}
