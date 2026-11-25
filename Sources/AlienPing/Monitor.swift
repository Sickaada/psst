import AppKit
import ApplicationServices
import AlienCore

private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}
private func frame(_ element: AXUIElement) -> CGRect? {
    guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero; var size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point), AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}

/// Reads the notification process only. No screen capture or window-image APIs.
private final class SnapshotReader {
    var elements: [String: AXUIElement] = [:]
    var visited = 0
    var semanticBanners = 0
    var attributedDescriptions = 0
    var errors: [Int: Int] = [:]
    var incomplete = false
    private let deadline = Date().addingTimeInterval(1.2)
    func read(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        guard Date() < deadline else { incomplete = true; return nil }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if error == .success { return value }
        if error != .attributeUnsupported && error != .noValue {
            errors[Int(error.rawValue), default: 0] += 1
            incomplete = true
        }
        return nil
    }
    private func text(_ value: CFTypeRef?) -> String {
        guard let value else { return "" }
        if let plain = value as? String { return plain }
        if CFGetTypeID(value) == CFAttributedStringGetTypeID() {
            return CFAttributedStringGetString(unsafeBitCast(value, to: CFAttributedString.self)) as String
        }
        return ""
    }
    func snapshot(_ element: AXUIElement, depth: Int = 0) -> NotificationNode? {
        guard depth < 14, visited < 500, Date() < deadline else { incomplete = true; return nil }
        visited += 1
        elements[String(CFHash(element))]=element
        let role = text(read(element, kAXRoleAttribute))
        let subrole = text(read(element, kAXSubroleAttribute))
        if BannerParser.bannerSubroles.contains(subrole) { semanticBanners += 1 }
        let attributed = text(read(element, "AXAttributedDescription"))
        if !attributed.isEmpty { attributedDescriptions += 1 }
        let description = attributed.isEmpty ? text(read(element, kAXDescriptionAttribute)) : attributed
        let value = role == kAXStaticTextRole ? text(read(element, kAXValueAttribute)) : ""
        var size = CGSize.zero
        if let ref = read(element, kAXSizeAttribute), CFGetTypeID(ref) == AXValueGetTypeID() {
            _ = AXValueGetValue(unsafeBitCast(ref, to: AXValue.self), .cgSize, &size)
        }
        // Do not traverse the notification history panel.
        let children = subrole == "AXNotificationCenter" ? [] : (read(element, kAXChildrenAttribute) as? [AXUIElement] ?? [])
        return NotificationNode(id: String(CFHash(element)), role: role, subrole: subrole, description: description, text: value, width: size.width, height: size.height, children: children.compactMap { snapshot($0, depth: depth+1) })
    }
}

final class NotificationMonitor {
    unowned let model: Model
    private var timer: Timer?
    private var tracker = PresenceTracker()
    private var moved: [(AXUIElement, CGPoint)] = []
    private let worker = DispatchQueue(label: "AlienPing.notification-reader", qos: .utility)
    private var busy = false
    private var stopped = false
    private var lastPhase = ""
    private var lastSummary = ""
    private var lastStateWrite = Date.distantPast
    private var lastSnapshotLog = Date.distantPast
    private var received = 0
    private var lastSource = ""
    private var lastPID: pid_t?
    init(model: Model) { self.model = model }
    func start() {
        stopped = false
        Diagnostics.shared.event("monitor_started", ["version": Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown"])
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        tick()
    }
    func stop() { stopped = true; timer?.invalidate(); restore(); Diagnostics.shared.event("monitor_stopped") }
    func restore() {
        for (element, original) in moved {
            var point = original
            if let value = AXValueCreate(.cgPoint, &point) { _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) }
        }
        moved.removeAll()
    }
    private func phase(_ phase: String, message: String? = nil) {
        let changed = phase != lastPhase
        if changed {
            Diagnostics.shared.event("monitor_state", ["state": phase, "trusted": model.trusted, "enabled": model.enabled])
            lastPhase = phase
        }
        if let message, (changed || received == 0) && model.status != message { model.status = message }
        if changed || Date().timeIntervalSince(lastStateWrite) >= 5 {
            lastStateWrite = Date()
            Diagnostics.shared.state(["state": phase, "trusted": model.trusted, "enabled": model.enabled, "hideOriginal": model.replace, "received": received, "lastSource": lastSource, "apps": model.availableApps.map(\.rawValue), "codexNamedChatGPT": model.sourceAliases["chatgpt"] == .codex])
        }
    }
    private func openOriginal(_ element: AXUIElement, expected: ParsedNotification, aliases: [String:SourceApp]) {
        Diagnostics.shared.event("open_chat_requested",["app":expected.source.rawValue])
        worker.async { [weak self] in
            guard let self else { return }
            // Re-read before acting: Notification Center can recycle a banner's AX element.
            let reader=SnapshotReader()
            let current=reader.snapshot(element).flatMap { BannerParser.parse($0,aliases:aliases).first }
            guard !reader.incomplete, let current,
                  current.id == expected.id, current.source == expected.source,
                  current.title == expected.title, current.body == expected.body else {
                self.openFallback(expected.source,reason:"expired_or_replaced");return
            }
            var names:CFArray?
            guard AXUIElementCopyActionNames(element,&names) == .success,
                  let actions=names as? [String],let action=NotificationOpenAction.select(actions) else {
                self.openFallback(expected.source,reason:"open_action_unavailable");return
            }
            AXUIElementSetMessagingTimeout(element,1.0)
            let result=AXUIElementPerformAction(element,action as CFString)
            Diagnostics.shared.event("open_chat_action_result",["app":expected.source.rawValue,"result":result.rawValue])
            // A timeout may occur after the app already handled the action. Do not click twice.
            if result == .success || result == .cannotComplete {
                DispatchQueue.main.async {
                    self.model.status = result == .success ? "Sent the original notification’s Open action to \(expected.source.rawValue)." : "Sent the chat-open request; macOS did not confirm completion."
                }
            } else { self.openFallback(expected.source,reason:"native_action_failed") }
        }
    }
    private func openFallback(_ source:SourceApp,reason:String) {
        Diagnostics.shared.event("open_chat_fallback",["app":source.rawValue,"reason":reason])
        DispatchQueue.main.async {
            self.model.openSource(source)
            self.model.status="The original notification is no longer available to open its chat. Opened \(source.rawValue) instead."
        }
    }
    private func tick() {
        guard !stopped else { return }
        let trusted=AXIsProcessTrusted()
        if model.trusted != trusted { model.trusted=trusted }
        guard model.trusted, model.enabled else {
            if !model.enabled { model.overlay.stop() }
            phase(model.trusted ? "paused" : "permission_required", message: model.trusted ? "Paused. Previews still work." : "Accessibility access is required. Click Connect to enable Psst.")
            restore(); tracker = PresenceTracker(); return
        }
        if !model.replace && !model.attention.isQuiet { restore() }
        guard !busy else { return }
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
            phase("waiting_for_process", message: "Waiting for macOS Notification Center…"); return
        }
        if lastPID != process.processIdentifier { tracker = PresenceTracker(); lastPID = process.processIdentifier }
        busy = true
        let pid = process.processIdentifier
        let aliases = model.sourceAliases
        worker.async { [weak self] in
            guard let self else { return }
            let root = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root, 0.08)
            let reader = SnapshotReader()
            let windows = reader.read(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
            var candidates: [(String, Ping, AXUIElement, Bool)] = []
            var dimensions: [String] = []
            var hostSafety: [CFHashCode: (Bool, SourceApp?)] = [:]
            for window in windows {
                guard let snapshot = reader.snapshot(window) else { continue }
                dimensions.append("\(Int(snapshot.width))x\(Int(snapshot.height))")
                let parsed = BannerParser.parse(snapshot, aliases: aliases)
                hostSafety[CFHash(window)] = (BannerParser.canHideHost(snapshot, aliases: aliases), parsed.first?.source)
                for notification in parsed {
                    // Payload is used in memory only, never in diagnostic output.
                    var fingerprint = Hasher()
                    fingerprint.combine(notification.title); fingerprint.combine(notification.body)
                    let key = "\(pid)|\(notification.id)|\(notification.source.rawValue)|\(fingerprint.finalize())"
                    let compact = BannerParser.canHideHost(snapshot, aliases: aliases)
                    var ping=Ping(source: notification.source, title: notification.title, body: notification.body)
                    if let target=reader.elements[notification.id] {
                        ping.openNotification = { [weak self] in self?.openOriginal(target,expected:notification,aliases:aliases) }
                    }
                    candidates.append((key, ping, window, compact))
                }
            }
            let summary = "windows=\(windows.count);sizes=\(dimensions.joined(separator: ","));nodes=\(reader.visited);banners=\(reader.semanticBanners);attributed=\(reader.attributedDescriptions);matched=\(candidates.count);incomplete=\(reader.incomplete);errors=\(reader.errors)"
            DispatchQueue.main.async {
                self.busy = false
                guard !self.stopped, self.model.enabled, self.model.trusted else { return }
                if summary != self.lastSummary || Date().timeIntervalSince(self.lastSnapshotLog) > 30 {
                    self.lastSummary = summary; self.lastSnapshotLog = Date()
                    Diagnostics.shared.event("scan", ["windows": windows.count, "sizes": dimensions, "nodes": reader.visited, "bannerNodes": reader.semanticBanners, "attributedDescriptions": reader.attributedDescriptions, "matches": candidates.count, "incomplete": reader.incomplete, "axErrors": Dictionary(uniqueKeysWithValues: reader.errors.map { (String($0.key), $0.value) })])
                }
                // A failed read isn't an empty screen. Preserve dedupe across transient errors.
                guard !reader.incomplete else {
                    self.phase("read_retry", message: "macOS notification read needs a retry. Diagnostics recorded.")
                    return
                }
                // Restore a shared host immediately if it gains an unrelated notification
                // or becomes a history panel. Never hide a mixed notification host.
                self.moved.removeAll { element, original in
                    guard let (safe, source) = hostSafety[CFHash(element)] else { return frame(element) == nil }
                    if safe, let source, self.model.accepts(source) { return false }
                    var point = original
                    if let value = AXValueCreate(.cgPoint, &point) {
                        let result = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
                        Diagnostics.shared.event("restore_native_host", ["result": result.rawValue])
                        return result == .success || result == .invalidUIElement
                    }
                    return false
                }
                self.phase("listening", message: "Connected. Waiting for a real notification; previews don’t count.")
                let fresh = self.tracker.fresh(Set(candidates.map { $0.0 }))
                self.moved.removeAll { frame($0.0) == nil }
                for (key, ping, window, compact) in candidates where fresh.contains(key) {
                    guard self.model.accepts(ping.source) else {
                        Diagnostics.shared.event("source_disabled", ["app": ping.source.rawValue]); continue
                    }
                    self.received += 1; self.lastSource = ping.source.rawValue
                    self.model.attention.receive(ping)
                    self.model.status = "Received \(self.received) · Last: \(ping.source.rawValue) at \(Date().formatted(date: .omitted, time: .shortened))."
                    Diagnostics.shared.event("notification_received", ["app": ping.source.rawValue, "count": self.received])
                    self.lastStateWrite = .distantPast; self.phase("listening")
                    if (self.model.replace || self.model.attention.isQuiet) && compact && !self.moved.contains(where: { CFEqual($0.0, window) }), let original = frame(window)?.origin {
                        var point = CGPoint(x: -20000, y: -20000)
                        if let value = AXValueCreate(.cgPoint, &point) {
                            let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
                            Diagnostics.shared.event("move_native_banner", ["result": result.rawValue])
                            if result == .success { self.moved.append((window, original)) }
                        }
                    }
                }
            }
        }
    }
}
