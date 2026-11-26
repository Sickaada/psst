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
        var clock=0.0
        let state=VineState(defaults:defaults),controller=VineController(model:model,state:VineState(defaults:defaults),now:{clock})
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
        controller.state.toggle(hasItems:false,quiet:false);settle()
        try require(controller.layoutEvidence.frame.width==372,"Empty compact button must expand the vine, not open the tray")
        controller.state.toggle(hasItems:false,quiet:false)
        controller.state.expanded=true
        // Exercise the actual hook writer and import path without notifying the desktop.
        let thread=UUID(),turn=UUID()
        let hookData=try JSONEncoder().encode(["session_id":thread.uuidString,"turn_id":turn.uuidString,"hook_event_name":"Stop","last_assistant_message":"Fixture reply"])
        let spool=dir.appendingPathComponent("codex-events")
        try CodexHook.record(hookData,in:spool,keepText:true)
        model.attention.importCodexEvents()
        try require(model.attention.inbox.entries.first?.chatID==thread,"Hook must enter the tray with real route identity")
        try CodexHook.record(hookData,in:spool,keepText:true)
        model.attention.importCodexEvents()
        try require(model.attention.inbox.entries.count==1,"Retried hook must not duplicate the turn")
        try require(try FileManager.default.contentsOfDirectory(atPath:spool.path).isEmpty,"Imported hook should leave the spool")
        model.attention.clear()
        let first=InboxEntry(source:.claude,title:"Fixture",body:"")
        model.attention.inbox.insert(first)
        settle()
        try require(controller.layoutEvidence.frame.width==372,"Unread item must expand the vine")
        try require(controller.layoutEvidence.targets.count>=3,"Header, notification and tray controls must expose hit targets")
        try require(!controller.layoutEvidence.targets.contains{$0.contains(CGPoint(x:10,y:100))},"Decorative stem must pass clicks through")
        try require(!controller.layoutEvidence.targets.contains{$0.contains(CGPoint(x:369,y:100))},"Transparent trailing margin must pass clicks through")
        try require(controller.layoutEvidence.targets.contains{$0.width>=52 && $0.contains(CGPoint(x:26,y:controller.layoutEvidence.frame.height/2))},"Large compact button must be centered vertically")
        model.attention.markRead(first.id);settle()
        try require(controller.layoutEvidence.frame.width==76,"Mark read must remove the final leaf")
        for i in 0..<200 { model.attention.inbox.insert(InboxEntry(source:i%2==0 ? .claude:.codex,title:"Sample \(i)",body:"")) }
        settle()
        try require(controller.layoutEvidence.frame.height <= (NSScreen.screens.first?.visibleFrame.height ?? 0)-24,"Large tray must fit the display")
        let h=controller.layoutEvidence.frame.height
        try require(controller.layoutEvidence.targets.allSatisfy{$0.minY>=0 && $0.maxY<=h},"Offscreen rows must not expose hit targets outside panel")
        controller.hide();controller.open();settle()
        try require(controller.state.enabled && controller.layoutEvidence.frame.width==372,"Open must reveal a hidden vine")
        model.attention.quietReason="Test quiet";settle()
        try require(controller.layoutEvidence.frame.width==76,"Quiet mode must collapse the vine")
        controller.open();settle()
        try require(controller.layoutEvidence.frame.width==372,"Explicit open during quiet must work")
        clock += 21;settle()
        try require(controller.layoutEvidence.frame.width==76,"Inactive vine must collapse")
        model.attention.quietReason="";settle()
        try require(controller.layoutEvidence.frame.width==76,"Manual collapse must persist after quiet ends")
        state.expanded=false
        try require(!VineState(defaults:defaults).expanded,"Collapse setting must survive restart")
        state.enabled=false
        try require(!VineState(defaults:defaults).enabled,"Hide setting must survive restart")
        print("Vine offscreen checks passed: empty/unread/read transitions, 200 items, viewport bounds, decorative click-through, quiet mode and persisted collapse.")
    }
}
