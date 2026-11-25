import Foundation
import CoreGraphics
import AlienCore
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { if a != b { print("FAIL: \(a) != \(b)"); exit(1) } }
func XCTAssertNil<T>(_ a: T?) { if a != nil { print("FAIL: expected nil"); exit(1) } }
struct CoreTests {
    func testRecognizesEachAppCaseInsensitively() {
        for app in SourceApp.allCases { XCTAssertEqual(Rules.source(labels: [app.rawValue.uppercased(), "New message"]), app) }
    }
    func testDoesNotMistakeMessageMentionForSource() {
        XCTAssertNil(Rules.source(labels: ["Mail", "Try Slack today"]))
        XCTAssertNil(Rules.source(labels: ["Mail", "Sender", "Subject", "Slack"]))
    }
    func testBannerDeliveredOnceWhileVisibleAndAgainAfterRemoval() {
        var tracker = PresenceTracker()
        XCTAssertEqual(tracker.fresh(["a"]), ["a"])
        XCTAssertEqual(tracker.fresh(["a"]), [])
        XCTAssertEqual(tracker.fresh(["a", "b"]), ["b"])
        XCTAssertEqual(tracker.fresh([]), [])
        XCTAssertEqual(tracker.fresh(["a"]), ["a"])
    }
}

let tests = CoreTests()
tests.testRecognizesEachAppCaseInsensitively()
tests.testDoesNotMistakeMessageMentionForSource()
tests.testBannerDeliveredOnceWhileVisibleAndAgainAfterRemoval()
print("All routing and delivery tests passed")

func textNode(_ id: String, _ text: String) -> NotificationNode {
    NotificationNode(id: id, role: "AXStaticText", text: text)
}
let claudeBanner = NotificationNode(id: "banner-1", subrole: "AXNotificationCenterBanner", description: "CLAUDE, Task complete, Ready to review", children: [textNode("title", "Task complete"), textNode("body", "Ready to review")])
let largeHost = NotificationNode(id: "host", role: "AXWindow", width: 1512, height: 982, children: [claudeBanner])
let parsed = BannerParser.parse(largeHost)
XCTAssertEqual(parsed.count, 1)
XCTAssertEqual(parsed.first?.source, .claude)
XCTAssertEqual(parsed.first?.title, "Task complete")
XCTAssertEqual(parsed.first?.body, "Ready to review")
let second = NotificationNode(id: "banner-2", subrole: "AXNotificationCenterAlert", description: "Slack, Hello", children: [textNode("title", "Hello")])
let stack = NotificationNode(id: "stack", subrole: "AXNotificationCenterBannerStack", children: [claudeBanner, second])
XCTAssertEqual(BannerParser.parse(stack).map(\.source), [.claude, .slack])
let history = NotificationNode(id: "history", role: "AXWindow", subrole: "AXNotificationCenter", width: 400, height: 900, children: [textNode("app", "Claude"), textNode("title", "Old task")])
XCTAssertEqual(BannerParser.parse(history).count, 0)
let unsupported = NotificationNode(id: "mail", subrole: "AXNotificationCenterBanner", description: "Mail, Claude, Try Slack", children: [textNode("title", "Claude"), textNode("body", "Try Slack")])
XCTAssertEqual(BannerParser.parse(unsupported).count, 0)
let legacy = NotificationNode(id: "legacy", role: "AXWindow", width: 380, height: 120, children: [textNode("app", "Claude"), textNode("title", "Legacy notification")])
XCTAssertEqual(BannerParser.parse(legacy).first?.title, "Legacy notification")
print("All notification structure regression tests passed")

XCTAssertEqual(BannerParser.canHideHost(largeHost), true)
XCTAssertEqual(BannerParser.canHideHost(history), false)
let mixedHost = NotificationNode(id: "mixed-host", role: "AXWindow", width: 1512, height: 982, children: [claudeBanner, unsupported])
XCTAssertEqual(BannerParser.canHideHost(mixedHost), false)
let twoSupported = NotificationNode(id: "two", role: "AXWindow", width: 1512, height: 982, children: [claudeBanner, second])
XCTAssertEqual(BannerParser.canHideHost(twoSupported), false)
XCTAssertEqual(BannerParser.canHideHost(legacy), true)
print("All native banner hiding tests passed")

let installedAliases: [String: SourceApp] = ["chatgpt": .codex]
XCTAssertEqual(Rules.source(labels: ["ChatGPT"], aliases: installedAliases), .codex)
XCTAssertNil(Rules.source(labels: ["ChatGPT"]))
let codexNative = NotificationNode(id: "codex", subrole: "AXNotificationCenterBanner", description: "ChatGPT, Task finished, Ready", children: [textNode("app", "ChatGPT"), textNode("title", "Task finished"), textNode("body", "Ready")])
let codexHost = NotificationNode(id: "codex-host", role: "AXWindow", width: 1512, height: 982, children: [codexNative])
XCTAssertEqual(BannerParser.parse(codexHost, aliases: installedAliases).first?.source, .codex)
XCTAssertEqual(BannerParser.parse(codexHost, aliases: installedAliases).first?.title, "Task finished")
XCTAssertEqual(BannerParser.canHideHost(codexHost, aliases: installedAliases), true)
XCTAssertEqual(BannerParser.parse(unsupported, aliases: installedAliases).count, 0)
print("All installed-name alias tests passed")

var destinations = Set<String>()
var starts = Set<String>()
var entryEdges = Set<String>()
for bounds in [CGRect(x:0,y:25,width:1512,height:930),CGRect(x:-1920,y:0,width:1920,height:1080),CGRect(x:100,y:50,width:320,height:600)] {
    for app in [SourceApp.claude, .codex] {
        for placement in ["Surprise me","Top left","Top right","Bottom left","Bottom right"] {
            for seed in 1...100 {
                let plan = CourierPlan.make(source: app, bounds: bounds, placement: placement, seed: UInt64(seed))
                XCTAssertEqual(bounds.contains(plan.actorFrame), true)
                XCTAssertEqual(bounds.contains(plan.bubbleFrame), true)
                XCTAssertEqual(plan.bubbleFrame.contains(plan.actorFrame), true)
                XCTAssertEqual(plan.actorFrame.width <= 72, true)
                XCTAssertEqual(plan.bubbleFrame.height <= 152, true)
                XCTAssertEqual(plan.position(0),plan.entry)
                XCTAssertEqual(plan.position(1),plan.actorFrame.origin)
                XCTAssertEqual(plan.position(0,departing:true),plan.actorFrame.origin)
                XCTAssertEqual(plan.position(1,departing:true),plan.exit)
                if placement == "Surprise me" {
                    destinations.insert("\(plan.actorFrame.minX),\(plan.actorFrame.minY)")
                    starts.insert("\(plan.entry.x),\(plan.entry.y)")
                    entryEdges.insert(plan.edge.rawValue)
                    let fixed = CourierPlan.make(source:app,bounds:bounds,placement:"Top right",seed:UInt64(seed))
                    XCTAssertEqual(plan.bubbleFrame,fixed.bubbleFrame)
                }
                switch plan.edge {
                case .left: XCTAssertEqual(plan.entry.x < bounds.minX,true)
                case .right: XCTAssertEqual(plan.entry.x > bounds.maxX,true)
                case .top: XCTAssertEqual(plan.entry.y > bounds.maxY,true)
                case .bottom: XCTAssertEqual(plan.entry.y < bounds.minY,true)
                }
                XCTAssertEqual(plan.entryDuration >= 0.9 && plan.entryDuration <= 2.2,true)
            }
        }
    }
}
XCTAssertEqual(destinations.count, 3)
XCTAssertEqual(starts.count > 200, true)
XCTAssertEqual(entryEdges.count, 4)
print("All motion geometry tests passed (3,000 plans)")

var clock = NotificationClock()
clock.advance(by:0.6,hovered:false,entrance:0.5,hold:7)
let beforeHover = clock.elapsed
clock.advance(by:60,hovered:true,entrance:0.5,hold:7)
XCTAssertEqual(clock.elapsed,beforeHover)
clock.advance(by:2,hovered:false,entrance:0.5,hold:7)
XCTAssertEqual(clock.elapsed,beforeHover+2)
print("Hover pauses notification expiry")
var entranceClock = NotificationClock()
entranceClock.advance(by:1,hovered:true,entrance:0.5,hold:7)
XCTAssertEqual(entranceClock.elapsed,0.5)
entranceClock.advance(by:7.1,hovered:false,entrance:0.5,hold:7)
entranceClock.advance(by:1,hovered:true,entrance:0.5,hold:7)
XCTAssertEqual(entranceClock.elapsed,8.6)
print("Hover preserves entrance and does not restart departure")

let manifestURL = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/mascots.json")
let manifest = try JSONDecoder().decode(MascotManifest.self,from:Data(contentsOf:manifestURL))
try manifest.validate()
for character in manifest.characters {
    let idle=character.animations["idle"]!
    XCTAssertEqual((18...25).contains(idle.sequence.count),true)
    XCTAssertEqual(Set(idle.sequence).count > 1,character.motionClass != "run")
    XCTAssertEqual(Set(character.animations["travel"]!.sequence).count > 1,true)
    XCTAssertEqual(idle.frameIndex(at:idle.duration+0.001),idle.sequence[0])
}
let screen=CGRect(x:-1920,y:24,width:1920,height:1056)
var perimeterStarts=Set<String>()
for seed in 1...200 {
    let flight=MascotFlight(bounds:screen,anchor:CGPoint(x:-60,y:900),seed:UInt64(seed))
    perimeterStarts.insert("\(flight.start)")
    for step in 0...150 {
        let t=Double(step)/150*flight.duration
        let sample=flight.sample(at:t)
        let rect=CGRect(x:sample.position.x-sample.size/2,y:sample.position.y-sample.size/2,width:sample.size,height:sample.size)
        XCTAssertEqual(sample.phase == .idle ? screen.contains(rect) : screen.insetBy(dx:-0.001,dy:-0.001).contains(sample.position),true)
        XCTAssertEqual(sample.size >= 63 && sample.size <= 104,true)
        XCTAssertEqual(sample.opacity >= 0 && sample.opacity <= 1,true)
        XCTAssertEqual(flight.sample(at:t,reduced:true).position,flight.anchor)
    }
    XCTAssertEqual(flight.sample(at:flight.entrance).phase == .idle,true)
    XCTAssertEqual(flight.sample(at:flight.duration).phase == .finished,true)
}
XCTAssertEqual(perimeterStarts.count > 190,true)
print("Sprite manifest/timing and 30,200 safe-frame flight samples passed")

// Catches skipped styles and repeated styles at shuffled-cycle boundaries.
var styles=MascotStyleBag()
var previous:MascotStyle?
for _ in 0..<100 {
    var cycle=Set<MascotStyle>()
    for _ in 0..<8 {
        let style=styles.next()
        XCTAssertEqual(style != previous,true)
        cycle.insert(style);previous=style
    }
    XCTAssertEqual(cycle.count,8)
}
for style in MascotStyle.allCases {
    for seed in 1...20 {
        let f=MascotFlight(bounds:screen,anchor:CGPoint(x:-150,y:850),seed:UInt64(seed),style:style)
        for i in 0...100 {
            let sample=f.sample(at:Double(i)/100*f.duration)
            XCTAssertEqual(screen.insetBy(dx:-0.001,dy:-0.001).contains(sample.position),true)
            XCTAssertEqual(f.sample(at:Double(i)/100*f.duration,reduced:true).position,f.anchor)
        }
    }
}
print("Eight-style shuffle cycles and screen-edge trajectories passed")

// Never confuse Close/Options with the original notification's Open action.
XCTAssertEqual(NotificationOpenAction.select(["AXCancel","AXPress"]),"AXPress")
XCTAssertEqual(NotificationOpenAction.select(["Name: Close\nIdentifier: close","Name: Open\nIdentifier: default"]),"Name: Open\nIdentifier: default")
XCTAssertNil(NotificationOpenAction.select(["Name: Close\nIdentifier: Open","AXShowMenu"]))
XCTAssertNil(NotificationOpenAction.select([]))
print("Notification open action selection passed")

let now=Date(timeIntervalSince1970:1000000)
var inbox=InboxState()
let missed=InboxEntry(source:.claude,title:"Private title",body:"Private text",date:now)
inbox.insert(missed,now:now);inbox.insert(missed,now:now)
XCTAssertEqual(inbox.entries.count,1)
let scrubbed=try JSONDecoder().decode(InboxState.self,from:inbox.encoded(storeContent:false))
XCTAssertEqual(scrubbed.entries[0].title,"")
XCTAssertEqual(scrubbed.entries[0].body,"")
inbox.markRead(missed.id);XCTAssertEqual(inbox.unreadCount,0)
inbox.prune(now:now.addingTimeInterval(8*86400));XCTAssertEqual(inbox.entries.count,0)
var delivery=AttentionQueue()
delivery.enqueue(missed.id,at:0,quiet:false)
XCTAssertEqual(delivery.flush(at:1,quiet:false).count,0)
XCTAssertEqual(delivery.flush(at:2.1,quiet:false),[missed.id])
delivery.enqueue(missed.id,at:3,quiet:true)
XCTAssertEqual(delivery.flush(at:20,quiet:true).count,0)
XCTAssertEqual(delivery.flush(at:21,quiet:false),[missed.id])
XCTAssertEqual(delivery.flush(at:22,quiet:false).count,0)
XCTAssertEqual(MeetingEvidence.active(context:"Google Meet",buttons:["Join now"]),false)
XCTAssertEqual(MeetingEvidence.active(context:"Google Meet",buttons:["Leave call"]),true)
XCTAssertEqual(MeetingEvidence.active(context:"Zoom Meeting",buttons:["Leave Meeting"]),true)
XCTAssertEqual(MeetingEvidence.active(context:"Unrelated document",buttons:["Leave call"]),false)
print("Inbox privacy, burst/quiet delivery and meeting evidence passed")
for edge in ScreenEdge.allCases {
    for seed in 1...30 {
        let flight=MascotFlight(bounds:screen,anchor:screen.origin,seed:UInt64(seed),edges:[edge])
        switch edge {
        case .left:XCTAssertEqual(flight.start.x,screen.minX)
        case .right:XCTAssertEqual(flight.start.x,screen.maxX)
        case .top:XCTAssertEqual(flight.start.y,screen.maxY)
        case .bottom:XCTAssertEqual(flight.start.y,screen.minY)
        }
    }
}
var subset=MascotStyleBag()
for _ in 0..<30 { XCTAssertEqual(subset.next(styles:[.portal]),.portal) }
for _ in 0..<50 { XCTAssertEqual([MascotStyle.portal,.floating].contains(subset.next(styles:[.portal,.floating])),true) }
for _ in 0..<250 { inbox.insert(InboxEntry(source:.codex,title:"test",body:"test",date:now),now:now) }
XCTAssertEqual(inbox.entries.count,200)
let restored=try JSONDecoder().decode(InboxState.self,from:inbox.encoded(storeContent:true))
XCTAssertEqual(restored.entries.first?.body,"test")
print("Selected edges, style filtering, retention cap and opt-in persistence passed")
var vineFixtures=(0..<8).map{InboxEntry(source:.claude,title:"Update \($0)",body:"Meaningful detail",date:now.addingTimeInterval(Double($0)))}
vineFixtures.append(InboxEntry(source:.claude,title:"",body:"",date:now))
vineFixtures.append(InboxEntry(source:.codex,title:"",body:"A useful body-only update",date:now))
vineFixtures.append(InboxEntry(source:.codex,title:"Read item",body:"",date:now,read:true))
let recentVine=VineSummary.recent(vineFixtures)
XCTAssertEqual(recentVine.count,6)
XCTAssertEqual(recentVine.first?.title,"Update 7")
XCTAssertEqual(recentVine.contains{$0.read},false)
XCTAssertEqual(VineSummary.recent([InboxEntry(source:.codex,title:"",body:"",date:now)]).count,0)
print("Vine shows the latest six individual unread notifications across apps, excluding records without saved text")
let visibleChat=FocusedChat(source:.codex,titles:["Notification vine refinement — Codex"])
XCTAssertEqual(visibleChat.matches(source:.codex,title:"Notification vine refinement",body:"Finished"),true)
XCTAssertEqual(visibleChat.matches(source:.claude,title:"Notification vine refinement",body:"Finished"),false)
XCTAssertEqual(visibleChat.matches(source:.codex,title:"Another conversation",body:"Notification vine refinement mentioned here"),false)
XCTAssertEqual(visibleChat.matches(source:.codex,title:"Task complete",body:"Chat: Notification vine refinement"),true)
XCTAssertEqual(FocusedChat(source:.codex,titles:["Task completed"]).matches(source:.codex,title:"Task completed",body:""),false)
XCTAssertEqual(FocusedChat(source:.claude,titles:["Claude"]).matches(source:.claude,title:"Claude",body:""),false)
XCTAssertEqual(FocusedChat(source:.codex,titles:[]).matches(source:.codex,title:"Notification vine refinement",body:""),false)
print("Foreground chat matching rejects other apps/chats, generic titles and arbitrary body mentions")

let storageDirectory=FileManager.default.temporaryDirectory.appendingPathComponent("PsstStorageTests-"+UUID().uuidString)
do {
    defer { try? FileManager.default.removeItem(at:storageDirectory) }
    try FileManager.default.createDirectory(at:storageDirectory,withIntermediateDirectories:true)
    var original=InboxState()
    let saved=InboxEntry(source:.codex,title:"Persistent chat",body:"Unicode 🌱 and 'quoted' text",read:true)
    original.insert(saved)
    let legacy=storageDirectory.appendingPathComponent("inbox.json")
    try original.encoded(storeContent:true).write(to:legacy)
    do {
        let store=try NotificationStore(directory:storageDirectory,storeContent:true)
        XCTAssertEqual(try store.load().entries,original.entries)
        XCTAssertEqual(FileManager.default.fileExists(atPath:legacy.path),false)
    }
    do {
        let reopened=try NotificationStore(directory:storageDirectory,storeContent:true)
        XCTAssertEqual(try reopened.load().entries,original.entries)
        try reopened.save(original,storeContent:false)
        XCTAssertEqual(try reopened.load().entries.first?.body,"")
        XCTAssertEqual(try reopened.load().entries.first?.read,true)
        try reopened.save(InboxState(),storeContent:true)
    }
    // A leftover old file must not resurrect cleared notifications.
    try original.encoded(storeContent:true).write(to:legacy)
    let cleared=try NotificationStore(directory:storageDirectory,storeContent:true)
    XCTAssertEqual(try cleared.load().entries.count,0)
    let attributes=try FileManager.default.attributesOfItem(atPath:cleared.url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue,0o600)
    print("SQLite migration, restart persistence, privacy scrubbing, read state, clear and file permissions passed")
} catch { print("FAIL: SQLite storage: \(error)");exit(1) }
