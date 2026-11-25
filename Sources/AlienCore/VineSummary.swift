import Foundation

public enum VineSummary {
    public static func previewable(_ entries:[InboxEntry])->[InboxEntry] {
        entries.filter {
            !$0.read && ($0.source == .claude || $0.source == .codex) &&
            (!$0.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !$0.body.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }.sorted{$0.date>$1.date}
    }
    public static func recent(_ entries:[InboxEntry],limit:Int=6)->[InboxEntry] {
        Array(previewable(entries).prefix(max(0,limit)))
    }
}
