import Foundation
public enum SourceApp: String, CaseIterable, Codable { case whatsapp = "WhatsApp", slack = "Slack", claude = "Claude", codex = "Codex" }
public enum Rules {
    public static func source(labels: [String], aliases: [String: SourceApp] = [:]) -> SourceApp? {
        guard let header = labels.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return SourceApp.allCases.first { $0.rawValue.caseInsensitiveCompare(header) == .orderedSame } ?? aliases[header.lowercased()]
    }
}
public struct PresenceTracker {
    private var previous: Set<String> = []
    public init() {}
    public mutating func fresh(_ keys: Set<String>) -> Set<String> {
        let added = keys.subtracting(previous)
        previous = keys
        return added
    }
}

// Value snapshots keep parsing independent of the live Accessibility process.
public struct NotificationNode {
    public var id: String
    public var role: String
    public var subrole: String
    public var description: String
    public var text: String
    public var width: Double
    public var height: Double
    public var children: [NotificationNode]
    public init(id: String, role: String = "AXGroup", subrole: String = "", description: String = "", text: String = "", width: Double = 0, height: Double = 0, children: [NotificationNode] = []) {
        self.id = id; self.role = role; self.subrole = subrole; self.description = description; self.text = text
        self.width = width; self.height = height; self.children = children
    }
}
public struct ParsedNotification {
    public var id: String
    public var source: SourceApp
    public var title: String
    public var body: String
}
public enum BannerParser {
    public static let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert", "AXNotificationCenterBannerStack", "AXNotificationCenterAlertStack"]
    public static func canHideHost(_ root: NotificationNode, aliases: [String: SourceApp] = [:]) -> Bool {
        func containsHistory(_ node: NotificationNode) -> Bool {
            node.subrole == "AXNotificationCenter" || node.role == "AXScrollArea" || node.children.contains(where: containsHistory)
        }
        guard root.role == "AXWindow", !containsHistory(root) else { return false }
        let banners = semanticBanners(root)
        if !banners.isEmpty { return banners.count == 1 && decode(banners[0], aliases: aliases) != nil }
        return root.width > 100 && root.width < 650 && root.height > 30 && root.height < 450 && parse(root, aliases: aliases).count == 1
    }
    public static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{200E}", with: "").replacingOccurrences(of: "\u{200F}", with: "").replacingOccurrences(of: "\u{200B}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func sourceDescription(_ value: String, aliases: [String: SourceApp] = [:]) -> SourceApp? {
        let header = clean(String(value.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""))
        return Rules.source(labels: [header], aliases: aliases)
    }
    public static func parse(_ root: NotificationNode, aliases: [String: SourceApp] = [:]) -> [ParsedNotification] {
        // An explicitly identified history panel must never be replayed as arrivals.
        guard root.subrole != "AXNotificationCenter" else { return [] }
        let semantic = semanticBanners(root)
        if !semantic.isEmpty { return semantic.compactMap { decode($0, aliases: aliases) } }
        // Compatibility for older compact windows without banner subroles.
        guard root.role == "AXWindow", root.width > 100, root.width < 650, root.height > 30, root.height < 450 else { return [] }
        return decode(root, aliases: aliases).map { [$0] } ?? []
    }
    private static func semanticBanners(_ node: NotificationNode) -> [NotificationNode] {
        guard node.subrole != "AXNotificationCenter" else { return [] }
        let nested = node.children.flatMap(semanticBanners)
        if !nested.isEmpty { return nested }
        return bannerSubroles.contains(node.subrole) ? [node] : []
    }
    private static func values(_ node: NotificationNode) -> [String] {
        let own = node.role == "AXStaticText" || node.role == "AXImage" ? [clean(node.text.isEmpty ? node.description : node.text)].filter { !$0.isEmpty } : []
        return own + node.children.flatMap(values)
    }
    private static func decode(_ node: NotificationNode, aliases: [String: SourceApp] = [:]) -> ParsedNotification? {
        var texts = values(node)
        // Source metadata has priority. Never search a message body for an app name.
        let metadata = clean(node.description)
        let source: SourceApp?
        if !metadata.isEmpty && !["Notification", "notification", "Notification Center"].contains(metadata) {
            source = sourceDescription(metadata, aliases: aliases)
        } else { source = Rules.source(labels: texts, aliases: aliases) }
        guard let source else { return nil }
        if let first = texts.first, Rules.source(labels: [first], aliases: aliases) == source { texts.removeFirst() }
        if texts.isEmpty && !metadata.isEmpty {
            texts = metadata.split(separator: ",", maxSplits: 2).dropFirst().map { clean(String($0)) }
        }
        return ParsedNotification(id: node.id, source: source, title: texts.first ?? "New notification", body: texts.dropFirst().joined(separator: "\n"))
    }
}

public enum NotificationOpenAction {
    /// Only the default click or explicitly named Open action; never Close/Options.
    public static func select(_ actions: [String]) -> String? {
        if let open=actions.first(where: { action in
            guard action.hasPrefix("Name:") else { return false }
            return String(action.dropFirst(5).prefix { $0 != "\n" }).trimmingCharacters(in:.whitespaces).lowercased() == "open"
        }) { return open }
        return actions.first { $0 == "AXPress" }
    }
}
