import AppKit
import SwiftUI
import AlienCore

enum ReadmePreview {
    @MainActor static func render(to directory:URL) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let model=Model()
        let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:temporary) }
        let attention=AttentionController(model:model,directory:temporary)
        attention.inbox.insert(InboxEntry(source:.claude,title:"Your research is ready",body:"The comparison and source notes are ready to review."))
        attention.inbox.insert(InboxEntry(source:.codex,title:"Build complete",body:"Your changes are ready. Take a look when you have a moment."))
        func save<V:View>(_ view:V,_ name:String) throws {
            let host=NSHostingView(rootView:view.environment(\.colorScheme,.light))
            let size=host.fittingSize
            host.frame=NSRect(origin:.zero,size:size)
            let window=NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView=host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until:Date().addingTimeInterval(0.15))
            guard let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw NSError(domain:"Preview",code:1) }
            host.cacheDisplay(in:host.bounds,to:rep)
            try rep.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name))
        }
        let suite="Psst.VinePreview."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let state=VineState(defaults:defaults)
        attention.inbox.insert(InboxEntry(source:.claude,title:"Draft finished",body:"",date:Date().addingTimeInterval(-420)))
        attention.inbox.insert(InboxEntry(source:.codex,title:"Tests passed",body:"",date:Date().addingTimeInterval(-240)))
        try save(VineView(attention:attention,model:model,state:state).frame(width:318,height:540).padding(22).background(Color(hex:"D7E2EB")),"vine.png")
        state.expanded=false
        try save(VineView(attention:attention,model:model,state:state).frame(width:76,height:116).padding(22).background(Color(hex:"D7E2EB")),"vine-collapsed.png")
        try save(AttentionView(attention:attention,model:model).frame(width:640,height:680),"tray.png")
        try save(AttentionView(attention:attention,model:model,tab:1).frame(width:680,height:1050),"personalize.png")
        try save(VStack(spacing:30) {
            PingView(ping:Ping(source:.claude,title:"Your research is ready",body:"A little update, delivered with personality."),color:Color(hex:"EDA47F"),hideText:false,open:{},dismiss:{})
            PingView(ping:Ping(source:.codex,title:"Build complete",body:"Your changes are ready to review."),color:Color(hex:"81C9ED"),hideText:false,open:{},dismiss:{})
        }.padding(40).background(Color(hex:"EAEFF5")),"bubbles.png")
    }
}
