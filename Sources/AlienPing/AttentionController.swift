import AppKit
import SwiftUI
import AlienCore

final class AttentionController: ObservableObject {
    unowned let model:Model
    @Published var inbox=InboxState()
    @Published var quietMode:String { didSet { UserDefaults.standard.set(quietMode,forKey:"quietMode") } }
    @Published var autoMeetings:Bool { didSet { UserDefaults.standard.set(autoMeetings,forKey:"autoMeetings");if autoMeetings { meetings.start() } else { meetings.stop() } } }
    @Published var quietAway:Bool { didSet { UserDefaults.standard.set(quietAway,forKey:"quietAway") } }
    @Published var storeContent:Bool { didSet { UserDefaults.standard.set(storeContent,forKey:"storeInboxContent");save() } }
    @Published var preferences:[String:CompanionPreferences] { didSet { if let d=try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(d,forKey:"companions") } } }
    @Published var quietReason=""
    @Published var meetingStatus="Checking for active calls…"
    @Published var storageError=""
    var isQuiet:Bool { !quietReason.isEmpty }
    var showInbox:(()->Void)?
    var onCountChanged:((Int)->Void)?
    private var queue=AttentionQueue()
    private var live:[UUID:Ping]=[:]
    private var timer:Timer?
    private var sessionUnavailable=false
    private var observers:[NSObjectProtocol]=[]
    let meetings=MeetingMonitor()
    private let focusedChat=FocusedChatMonitor()
    private let hookDirectory:URL
    private var store:NotificationStore?
    init(model:Model,directory:URL?=nil) {
        self.model=model
        let d=UserDefaults.standard
        quietMode=d.string(forKey:"quietMode") ?? "Automatic"
        autoMeetings=d.object(forKey:"autoMeetings") as? Bool ?? true
        quietAway=d.object(forKey:"quietAway") as? Bool ?? true
        storeContent=d.bool(forKey:"storeInboxContent")
        preferences=(d.data(forKey:"companions").flatMap { try? JSONDecoder().decode([String:CompanionPreferences].self,from:$0) }) ?? [:]
        let folder=directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Psst")
        hookDirectory=folder.appendingPathComponent("codex-events")
        do {
            let loaded=try NotificationStore(directory:folder,storeContent:storeContent)
            inbox=try loaded.load()
            store=loaded
        } catch { storageError="Couldn’t load the saved tray. Existing history has been kept untouched." }
    }
    func start() {
        if autoMeetings { meetings.start() }
        focusedChat.start { [weak self] context in self?.markFocusedRead(context) }
        let center=NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification,NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in self?.sessionUnavailable=true;self?.tick()})
        }
        for name in [NSWorkspace.didWakeNotification,NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in self?.sessionUnavailable=false;self?.tick()})
        }
        timer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true){[weak self] _ in self?.tick()}
        onCountChanged?(inbox.unreadCount);tick()
    }
    func stop() { timer?.invalidate();timer=nil;meetings.stop();focusedChat.stop();for token in observers { NSWorkspace.shared.notificationCenter.removeObserver(token) };observers=[];save() }
    func preference(_ source:SourceApp)->CompanionPreferences { preferences[source.rawValue] ?? CompanionPreferences(character:source == .claude ? "sunburst":"terminal") }
    func change(_ source:SourceApp,_ update:(inout CompanionPreferences)->Void) { var p=preference(source);update(&p);preferences[source.rawValue]=p }
    var vineOnly:Bool { UserDefaults.standard.double(forKey:"vineOnlyUntil") > Date().timeIntervalSince1970 }
    var onVineArrival:(()->Void)?
    func pauseBubbles() {
        UserDefaults.standard.set(Date().addingTimeInterval(1800).timeIntervalSince1970,forKey:"vineOnlyUntil")
        queue.clear();live.removeAll();model.overlay.stop()
    }
    func receive(_ ping:Ping) {
        focusedChat.inspect { [weak self] context in
            guard let self else { return }
            let seen = !self.sessionUnavailable && context?.matches(source:ping.source,title:ping.title,body:ping.body)==true
            let entry=InboxEntry(source:ping.source,title:ping.title,body:ping.body,read:seen)
            self.inbox.insert(entry)
            if !seen && self.vineOnly {
                if !self.isQuiet && !VineSummary.previewable([entry]).isEmpty { self.onVineArrival?() }
            } else if !seen {
                var livePing=ping;livePing.inboxIDs=[entry.id]
                self.live[entry.id]=livePing
                self.queue.enqueue(entry.id,at:Date.timeIntervalSinceReferenceDate,quiet:self.isQuiet)
            }
            self.save()
            Diagnostics.shared.event(seen ? "notification_already_visible":"inbox_received",["app":ping.source.rawValue,"quiet":self.isQuiet,"unread":self.inbox.unreadCount])
        }
    }
    private func markFocusedRead(_ context:FocusedChat) {
        guard !sessionUnavailable else { return }
        let ids=Set(inbox.entries.filter{!$0.read && context.matches(source:$0.source,title:$0.title,body:$0.body)}.map(\.id))
        guard !ids.isEmpty else { return }
        for id in ids { inbox.markRead(id);queue.remove(id);live.removeValue(forKey:id) }
        model.overlay.removeReadNotifications(ids)
        save()
        Diagnostics.shared.event("focused_chat_seen",["app":context.source.rawValue,"count":ids.count])
    }
    func markRead(_ id:UUID) { model.overlay.removeReadNotifications([id]);inbox.markRead(id);queue.remove(id);live.removeValue(forKey:id);save() }
    func markAllRead() { model.overlay.removeReadNotifications(Set(inbox.entries.map(\.id)));inbox.markAllRead();queue.clear();live.removeAll();save() }
    func remove(_ id:UUID) { model.overlay.removeReadNotifications([id]);inbox.remove(id);queue.remove(id);live.removeValue(forKey:id);save() }
    func clear() { model.overlay.removeReadNotifications(Set(inbox.entries.map(\.id)));inbox.clear();queue.clear();live.removeAll();save() }
    func open(_ entry:InboxEntry) {
        guard let url=entry.chatURL else { model.openSource(entry.source);return }
        guard let app=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.openai.codex") else { model.openSource(.codex);return }
        NSWorkspace.shared.open([url],withApplicationAt:app,configuration:NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if error != nil { DispatchQueue.main.async { self?.model.openSource(.codex) } }
        }
    }
    func importCodexEvents() {
        guard model.enabled, let store,
              let files=try? FileManager.default.contentsOfDirectory(at:hookDirectory,includingPropertiesForKeys:nil,options:.skipsHiddenFiles)
        else { return }
        var changed=false
        for file in files.filter({ $0.pathExtension == "json" }).prefix(32) {
            guard let data=try? Data(contentsOf:file), data.count <= 30000,
                  let entry=try? JSONDecoder().decode(InboxEntry.self,from:data),
                  entry.source == .codex, entry.chatID != nil, entry.id.uuidString.lowercased()==file.deletingPathExtension().lastPathComponent
            else { continue }
            if inbox.entries.contains(where:{ $0.id==entry.id }) {
                try? FileManager.default.removeItem(at:file); continue
            }
            var next=inbox;next.insert(entry)
            do {
                try store.save(next,storeContent:storeContent)
                inbox=next;changed=true;try FileManager.default.removeItem(at:file)
            } catch { storageError="Couldn’t save a Codex update.";break }
        }
        if changed { onCountChanged?(inbox.unreadCount) }
    }
    private func save() {
        onCountChanged?(inbox.unreadCount)
        do { guard let store else { return };try store.save(inbox,storeContent:storeContent);storageError="" }
        catch { storageError="Couldn’t save the tray. Check available disk space." }
    }
    private func tick() {
        importCodexEvents()
        let idle=CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType:CGEventType(rawValue:UInt32.max)!)
        let reason:String
        if quietMode == "Quiet" { reason="Quiet mode" }
        else if sessionUnavailable { reason="Mac asleep or session inactive" }
        else if quietMode == "Allow" { reason="" }
        else if autoMeetings && meetings.active { reason="Meeting detected" }
        else if quietAway && idle >= 120 { reason="Away from your Mac" }
        else { reason="" }
        let currentMeetingStatus=autoMeetings ? meetings.status : "Automatic meeting detection is off."
        if meetingStatus != currentMeetingStatus { meetingStatus=currentMeetingStatus }
        if reason != quietReason {
            quietReason=reason
            if !reason.isEmpty {
                model.overlay.stop()
                for entry in inbox.entries where !vineOnly && live[entry.id] != nil && !entry.read && Date().timeIntervalSince(entry.date)<15 { queue.enqueue(entry.id,at:Date.timeIntervalSinceReferenceDate,quiet:true) }
            }
            Diagnostics.shared.event("quiet_mode_changed",["quiet":!reason.isEmpty])
        }
        var pruned=inbox;pruned.prune()
        if pruned.entries.count != inbox.entries.count { inbox=pruned;save() }
        let valid=Set(inbox.entries.map(\.id));live=live.filter{valid.contains($0.key)}
        guard model.enabled else { return }
        let wasDeferred=queue.deferred
        let ids=queue.flush(at:Date.timeIntervalSinceReferenceDate,quiet:isQuiet)
        let entries=ids.compactMap { id in inbox.entries.first{$0.id==id && !$0.read} }
        guard !entries.isEmpty else { return }
        if entries.count == 1 && !wasDeferred, let entry=entries.first,var ping=live[entry.id] {
            let original=ping.openNotification
            if original == nil { ping.actionLabel="Open \(ping.source.rawValue)" }
            ping.openNotification={ [weak self] in self?.markRead(entry.id);if let original { original() } else { self?.model.openSource(entry.source) } }
            model.overlay.enqueue(ping)
        } else {
            let apps=Set(entries.map{$0.source.rawValue}).sorted().joined(separator:" and ")
            let count=entries.count
            var summary=Ping(source:entries[0].source,title:wasDeferred ? "While you were away" : "\(count) notifications are ready",body:"\(count) saved from \(apps). Catch up when you’re ready.")
            summary.inboxIDs=Set(entries.map(\.id))
            summary.actionLabel="Open tray"
            summary.openNotification={ [weak self] in self?.showInbox?() }
            model.overlay.enqueue(summary)
            Diagnostics.shared.event("notification_summary",["count":count,"catchUp":wasDeferred])
        }
        for id in ids { live.removeValue(forKey:id) }
    }
}
