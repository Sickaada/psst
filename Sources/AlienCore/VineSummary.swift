import Foundation

public struct VineGroup {
    public let source:SourceApp
    public let entries:[InboxEntry]
    public let totalCount:Int
    public let unsavedCount:Int
    public let moreCount:Int
    public var cardCount:Int { entries.count+(unsavedCount>0 ? 1:0) }
}
public enum VineSummary {
    /// A bounded preview of meaningful unread updates; the tray retains every item.
    public static func groups(_ entries:[InboxEntry],limit:Int=3)->[VineGroup] {
        [SourceApp.claude,.codex].compactMap { source in
            let unread=entries.filter{!$0.read && $0.source==source}.sorted{$0.date>$1.date}
            guard !unread.isEmpty else { return nil }
            let content=unread.filter{!$0.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !$0.body.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}
            let shown=Array(content.prefix(max(0,limit)))
            return VineGroup(source:source,entries:shown,totalCount:unread.count,unsavedCount:unread.count-content.count,moreCount:content.count-shown.count)
        }
    }
}
