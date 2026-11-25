import Foundation

public struct InboxEntry: Codable, Identifiable, Equatable {
    public var id:UUID
    public var source:SourceApp
    public var title:String
    public var body:String
    public var date:Date
    public var read:Bool
    public init(id:UUID=UUID(),source:SourceApp,title:String,body:String,date:Date=Date(),read:Bool=false) {
        self.id=id;self.source=source;self.title=String(title.prefix(500));self.body=String(body.prefix(4000));self.date=date;self.read=read
    }
}
public struct InboxState: Codable {
    public private(set) var entries:[InboxEntry]=[]
    public init() {}
    public var unreadCount:Int { entries.filter{!$0.read}.count }
    public mutating func insert(_ entry:InboxEntry,now:Date=Date()) {
        guard !entries.contains(where:{$0.id == entry.id}) else { return }
        entries.insert(entry,at:0);prune(now:now)
    }
    public mutating func prune(now:Date=Date()) { entries=Array(entries.filter{now.timeIntervalSince($0.date)<7*86400}.prefix(200)) }
    public mutating func markRead(_ id:UUID) { if let i=entries.firstIndex(where:{$0.id==id}) { entries[i].read=true } }
    public mutating func markAllRead() { for i in entries.indices { entries[i].read=true } }
    public mutating func remove(_ id:UUID) { entries.removeAll{$0.id==id} }
    public mutating func clear() { entries=[] }
    public func encoded(storeContent:Bool) throws -> Data {
        var copy=self
        if !storeContent { for i in copy.entries.indices { copy.entries[i].title="";copy.entries[i].body="" } }
        return try JSONEncoder().encode(copy)
    }
}
public struct AttentionQueue {
    private var pending:[UUID]=[]
    private var deadline:Double?
    public private(set) var deferred=false
    public init() {}
    public mutating func enqueue(_ id:UUID,at time:Double,quiet:Bool) {
        if !pending.contains(id) { pending.append(id) }
        if deadline == nil { deadline=time+2 }
        deferred = deferred || quiet
    }
    public mutating func flush(at time:Double,quiet:Bool) -> [UUID] {
        if quiet { if !pending.isEmpty { deferred=true };return [] }
        guard deferred || time >= (deadline ?? .infinity) else { return [] }
        let result=pending;pending=[];deadline=nil;deferred=false;return result
    }
    public mutating func remove(_ id:UUID) { pending.removeAll{$0==id};if pending.isEmpty { deadline=nil;deferred=false } }
    public mutating func clear() { pending=[];deadline=nil;deferred=false }
}
public enum MeetingEvidence {
    public static func active(context:String,buttons:[String]) -> Bool {
        let c=context.lowercased(), meet=c.contains("google meet") || c.contains("meet.google.com") || c.contains("meet -"), zoom=c.contains("zoom")
        guard meet || zoom else { return false }
        return buttons.contains { text in
            let s=text.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
            return (meet && s.hasPrefix("leave call")) || (zoom && (s.hasPrefix("leave meeting") || s.hasPrefix("end meeting") || s=="leave" || s=="end"))
        }
    }
}
public struct CompanionPreferences: Codable {
    public var character:String
    public var styles:[MascotStyle]
    public var edges:[ScreenEdge]
    public var calm:Bool
    public init(character:String) { self.character=character;styles=MascotStyle.allCases;edges=ScreenEdge.allCases;calm=false }
}
public enum ScreenEdge:String,CaseIterable,Codable { case left,right,top,bottom }
