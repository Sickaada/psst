import AppKit
import SwiftUI
import ApplicationServices
import AlienCore

enum Corner: String, CaseIterable, Identifiable {
    case random = "Surprise me", topLeft = "Top left", topRight = "Top right", bottomLeft = "Bottom left", bottomRight = "Bottom right"
    var id: String { rawValue }
}
extension SourceApp: Identifiable {
    public var id: String { rawValue }
    var defaultHex: String { switch self { case .whatsapp: return "77D69D"; case .slack: return "C4A5F5"; case .claude: return "EDA47F"; case .codex: return "81C9ED" } }
    var bundleID: String { switch self { case .whatsapp: return "net.whatsapp.WhatsApp"; case .slack: return "com.tinyspeck.slackmacgap"; case .claude: return "com.anthropic.claudefordesktop"; case .codex: return "com.openai.codex" } }
}
extension Color {
    init(hex: String) {
        let n = UInt64(hex, radix: 16) ?? 0x77D69D
        self.init(red: Double((n >> 16) & 255)/255, green: Double((n >> 8) & 255)/255, blue: Double(n & 255)/255)
    }
    var hex: String {
        guard let c = NSColor(self).usingColorSpace(.deviceRGB) else { return "77D69D" }
        return String(format: "%02X%02X%02X", Int(c.redComponent*255), Int(c.greenComponent*255), Int(c.blueComponent*255))
    }
}
struct Ping {
    let source: SourceApp
    let title: String
    let body: String
    var inboxIDs:Set<UUID> = []
    var actionLabel:String? = nil
    var preview = false
    var openNotification: (() -> Void)? = nil
}
final class Model: ObservableObject {
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "enabled") } }
    @Published var corner: Corner { didSet { UserDefaults.standard.set(corner.rawValue, forKey: "corner") } }
    @Published var duration: Double { didSet { UserDefaults.standard.set(duration, forKey: "duration") } }
    @Published var replace: Bool { didSet { UserDefaults.standard.set(replace, forKey: "replace") } }
    @Published var hideText: Bool { didSet { UserDefaults.standard.set(hideText, forKey: "hideText") } }
    @Published var trusted = false
    @Published var status = "Preview is ready. Connect notifications when you’re ready."
    @Published var selected: SourceApp = .codex
    @Published var availableApps: [SourceApp] = []
    var sourceAliases: [String: SourceApp] = [:]
    private var applicationURLs: [SourceApp: URL] = [:]
    @Published var colors: [String: String] { didSet { UserDefaults.standard.set(colors, forKey: "colors") } }
    @Published var disabled: [String] { didSet { UserDefaults.standard.set(disabled, forKey: "disabled") } }
    var overlay: OverlayController!
    var monitor: NotificationMonitor!
    var attention: AttentionController!
    init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: "enabled") as? Bool ?? true
        let savedCorner = Corner(rawValue: d.string(forKey: "corner") ?? "") ?? .topRight
        corner = savedCorner == .random ? .topRight : savedCorner
        duration = d.object(forKey: "duration") as? Double ?? 7
        replace = d.bool(forKey: "replace")
        hideText = d.bool(forKey: "hideText")
        colors = d.dictionary(forKey: "colors") as? [String: String] ?? [:]
        disabled = d.stringArray(forKey: "disabled") ?? []
        overlay = OverlayController(model: self)
        monitor = NotificationMonitor(model: self)
        attention = AttentionController(model:self)
        refreshApplications()
    }
    func refreshApplications() {
        var installed: [SourceApp] = []
        var aliases: [String: SourceApp] = [:]
        var urls: [SourceApp: URL] = [:]
        // The requested scope is now Claude and Codex, not a fixed four-app preset.
        for source in [SourceApp.claude, .codex] {
            let preferredNames = source == .codex ? ["Codex", "ChatGPT"] : ["Claude"]
            let preferred = preferredNames.flatMap { name in
                [URL(fileURLWithPath:"/Applications/\(name).app"),FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(name).app")]
            }
            let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID)
            let candidates = preferred + (resolved.map { [$0] } ?? [])
            guard let url = candidates.first(where: {
                FileManager.default.fileExists(atPath: $0.path) && Bundle(url: $0)?.bundleIdentifier == source.bundleID
            }), let bundle = Bundle(url: url) else { continue }
            installed.append(source); urls[source] = url
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let name = bundle.object(forInfoDictionaryKey: key) as? String {
                    let cleaned = BannerParser.clean(name).lowercased()
                    if !cleaned.isEmpty { aliases[cleaned] = source }
                }
            }
        }
        availableApps = installed; applicationURLs = urls; sourceAliases = aliases
        if !availableApps.contains(selected), let first = availableApps.first { selected = first }
        Diagnostics.shared.event("app_catalog", ["apps": installed.map(\.rawValue), "codexNamedChatGPT": aliases["chatgpt"] == .codex])
    }
    func accepts(_ source: SourceApp) -> Bool {
        availableApps.contains(source) && !disabled.contains(source.rawValue)
    }
    func color(_ app: SourceApp) -> Color { Color(hex: colors[app.rawValue] ?? app.defaultHex) }
    func preview(_ app: SourceApp? = nil) {
        let source = app ?? selected
        guard availableApps.contains(source) else { status = "Install Claude or Codex to preview its notifications."; return }
        overlay.enqueue(Ping(source: source, title: "Hello from \(source.rawValue)", body: "Your little messenger has landed. This is a preview notification.", preview: true))
    }
    func openPing(_ ping: Ping) {
        if let action=ping.openNotification { action() }
        else { openSource(ping.source) }
    }
    func openSource(_ source: SourceApp) {
        Diagnostics.shared.event("open_source_requested", ["app": source.rawValue])
        guard let url = applicationURLs[source], FileManager.default.fileExists(atPath: url.path) else {
            Diagnostics.shared.event("open_source_missing", ["app": source.rawValue])
            status = "Couldn’t find \(source.rawValue). Make sure it’s installed on this Mac."
            let alert = NSAlert()
            alert.messageText = "Couldn’t find \(source.rawValue)"
            alert.informativeText = "Install or open \(source.rawValue) once, then try again."
            alert.runModal()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            if let error {
                Diagnostics.shared.event("open_source_failed", ["app": source.rawValue, "code": (error as NSError).code])
                DispatchQueue.main.async { self?.status = "Couldn’t open \(source.rawValue): \(error.localizedDescription)" }
            } else { Diagnostics.shared.event("open_source_succeeded", ["app": source.rawValue]) }
        }
    }
    func connect() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}
