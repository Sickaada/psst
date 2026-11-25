import Foundation

public struct FocusedChat {
    public let source:SourceApp
    public let titles:[String]
    public init(source:SourceApp,titles:[String]) { self.source=source;self.titles=titles }
    public func matches(source:SourceApp,title:String,body:String)->Bool {
        guard self.source==source else { return false }
        var candidates=[title]
        for line in body.split(separator:"\n") {
            let parts=line.split(separator:":",maxSplits:1).map(String.init)
            if parts.count==2,["chat","conversation","thread"].contains(parts[0].trimmingCharacters(in:.whitespaces).lowercased()) { candidates.append(parts[1]) }
        }
        let active=Set(titles.map(Self.normalized).filter(Self.distinctive))
        return candidates.map(Self.normalized).filter(Self.distinctive).contains{active.contains($0)}
    }
    private static func distinctive(_ title:String)->Bool {
        let generic:Set<String>=["claude","codex","chatgpt","new chat","new notification","notification","task completed","task complete","build complete","response ready","your update is ready","update ready","new conversation","conversation","untitled","untitled chat","terminal","settings","workspace","new project","all projects","notifications","all chats","archived chats","recent chats","projects","code review"]
        return title.count>=8 && !generic.contains(title)
    }
    private static func normalized(_ value:String)->String {
        var title=value.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        for brand in ["claude","codex","chatgpt"] {
            for separator in [" — "," – "," - "," | "] {
                if title.hasSuffix(separator+brand) { title=String(title.dropLast(separator.count+brand.count)) }
                if title.hasPrefix(brand+separator) { title=String(title.dropFirst(brand.count+separator.count)) }
            }
        }
        return title.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
    }
}
