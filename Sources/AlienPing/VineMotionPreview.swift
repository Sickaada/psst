import AppKit
import SwiftUI
import AlienCore

/// Renders only an isolated sample view. Does not capture or record the display.
enum VineMotionPreview {
    @MainActor static func render(to directory:URL) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        for reduced in [false,true] {
            let folder=directory.appendingPathComponent(reduced ? "reduced":"normal")
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let model=Model(),temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let suite="Psst.MotionPreview."+UUID().uuidString
            let defaults=UserDefaults(suiteName:suite)!
            defer { defaults.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:temp) }
            let attention=AttentionController(model:model,directory:temp),state=VineState(defaults:defaults)
            attention.inbox.insert(InboxEntry(source:.codex,title:"Your update is ready",body:"A new notification arrives with a gentle fade."))
            let view=VineView(attention:attention,model:model,state:state).frame(width:372,height:330).padding(20).background(Color(hex:"D7E2EB")).environment(\.vineReducedPreview,reduced)
            let host=NSHostingView(rootView:view)
            host.frame=NSRect(x:0,y:0,width:412,height:370)
            let window=NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false);window.contentView=host
            let start=ProcessInfo.processInfo.systemUptime
            var measured:[Double]=[]
            for i in 0..<18 {
                if i>0 { RunLoop.current.run(until:Date().addingTimeInterval(0.035)) }
                if i==14 { attention.meetingStatus="Unrelated state update" }
                host.layoutSubtreeIfNeeded()
                guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw NSError(domain:"MotionPreview",code:1) }
                host.cacheDisplay(in:host.bounds,to:bitmap)
                measured.append(ProcessInfo.processInfo.systemUptime-start)
                try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("frame-\(i).png"))
            }
            let report:[String:Any]=["offscreen":true,"screenCapture":false,"reducedMotion":reduced,"measuredFrameTimes":measured,"duration":0.36,"interaction":"First appearance of a new unread row; unrelated meeting-status change at frame14", "trigger":"Native sample view first rendered at frame0; onAppear starts opacity clock", "frames":(0..<18).map{"frame-\($0).png"}, "limitations":"Offscreen SwiftUI frames only. Reduced motion uses a test environment override of the same immediate branch. Panel-level appearance and real pointer interactions not measured."]
            try JSONSerialization.data(withJSONObject:report,options:.prettyPrinted).write(to:folder.appendingPathComponent("report.json"))
        }
    }
}
