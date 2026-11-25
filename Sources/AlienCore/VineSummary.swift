import Foundation

public enum VineSummary {
    /// The latest six individual unread notifications across both supported apps.
    public static func recent(_ entries:[InboxEntry],limit:Int=6)->[InboxEntry] {
        Array(entries.filter{!$0.read && ($0.source == .claude || $0.source == .codex)}.sorted{$0.date>$1.date}.prefix(max(0,limit)))
    }
}
