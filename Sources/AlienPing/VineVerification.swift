import AppKit
import AlienCore

/// Isolated data and preferences; offscreen panel, no live notifications or screen capture.
enum VineVerification {
    static func run() throws {
        let model=Model()
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("PsstVineCheck-"+UUID().uuidString)
        let suite="Psst.VineCheck."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:dir) }
        model.attention=AttentionController(model:model,directory:dir)
        let state=VineState(defaults:defaults),controller=VineController(model:model,state:VineState(defaults:defaults))
        controller.start(present:false)
        defer { controller.stop() }
        func settle() {
            for _ in 0..<3 {
                RunLoop.current.run(until:Date().addingTimeInterval(0.2))
                controller.renderOffscreenForVerification()
            }
        }
        func require(_ condition:Bool,_ description:String) throws {
            if !condition { throw NSError(domain:"VineVerification",code:1,userInfo:[NSLocalizedDescriptionKey:description]) }
        }
        settle()
        try require(controller.layoutEvidence.frame.width==76,"Empty vine must be compact")
        let first=InboxEntry(source:.claude,title:"Fixture",body:"")
        model.attention.inbox.insert(first)
        settle()
        try require(controller.layoutEvidence.frame.width==420,"Unread item must expand the vine")
        try require(controller.layoutEvidence.targets.count>=3,"Header, notification and tray controls must expose hit targets")
        try require(!controller.layoutEvidence.targets.contains{$0.contains(CGPoint(x:10,y:100))},"Decorative stem must pass clicks through")
        try require(!controller.layoutEvidence.targets.contains{$0.contains(CGPoint(x:417,y:100))},"Transparent trailing margin must pass clicks through")
        model.attention.markRead(first.id);settle()
        try require(controller.layoutEvidence.frame.width==76,"Mark read must remove the final leaf")
        for i in 0..<200 { model.attention.inbox.insert(InboxEntry(source:i%2==0 ? .claude:.codex,title:"Sample \(i)",body:"")) }
        settle()
        try require(controller.layoutEvidence.frame.height <= (NSScreen.screens.first?.visibleFrame.height ?? 0)-24,"Large tray must fit the display")
        let h=controller.layoutEvidence.frame.height
        try require(controller.layoutEvidence.targets.allSatisfy{$0.minY>=0 && $0.maxY<=h},"Offscreen rows must not expose hit targets outside panel")
        model.attention.quietReason="Test quiet";settle()
        try require(controller.layoutEvidence.frame.width==76,"Quiet mode must collapse the vine")
        model.attention.quietReason="";controller.state.expanded=false;settle()
        try require(controller.layoutEvidence.frame.width==76,"Manual collapse must persist after quiet ends")
        state.expanded=false
        try require(!VineState(defaults:defaults).expanded,"Collapse setting must survive restart")
        state.enabled=false
        try require(!VineState(defaults:defaults).enabled,"Hide setting must survive restart")
        print("Vine offscreen checks passed: empty/unread/read transitions, 200 items, viewport bounds, decorative click-through, quiet mode and persisted collapse.")
    }
}
