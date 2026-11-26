import AppKit
import SwiftUI
import AlienCore

final class OverlayController {
    unowned let model:Model
    private var queue:[Ping]=[]
    private var cards:[UUID:(panel:NSPanel,anchor:CGPoint,ping:Ping,slot:Int)]=[:]
    private var stopping=false
    init(model:Model) { self.model=model }
    func enqueue(_ ping:Ping) {
        stopping=false
        Diagnostics.shared.event("overlay_queued",["app":ping.source.rawValue,"preview":ping.preview])
        if queue.count >= 6 { queue.removeFirst();Diagnostics.shared.event("queue_oldest_dropped") }
        queue.append(ping);presentAvailable()
    }
    private func presentAvailable() {
        guard !stopping,let screen=NSScreen.main ?? NSScreen.screens.first else { return }
        let bounds=screen.visibleFrame.insetBy(dx:16,dy:16)
        let capacity=max(1,min(3,Int(bounds.height/178)))
        while !queue.isEmpty && cards.count < capacity {
            let occupied=Set(cards.values.map(\.slot));guard let slot=(0..<capacity).first(where:{!occupied.contains($0)}) else { return }
            let ping=queue.removeFirst(),id=UUID()
            let width=min(CGFloat(452),bounds.width),height:CGFloat=198
            let x=model.corner == .topLeft || model.corner == .bottomLeft ? bounds.minX : bounds.maxX-width
            let bottom=model.corner == .bottomLeft || model.corner == .bottomRight
            let y=bottom ? bounds.minY+CGFloat(slot)*height : bounds.maxY-height-CGFloat(slot)*height
            let frame=CGRect(x:x,y:y,width:width,height:height)
            let anchor=CGPoint(x:frame.minX+32,y:frame.minY+38)
            let panel=NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false;panel.level = .floating
            panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.transient];panel.hidesOnDeactivate=false
            let dismiss:()->Void = { [weak self] in self?.dismiss(id) }
            panel.contentView=NSHostingView(rootView:PingView(ping:ping,color:model.color(ping.source),hideText:model.hideText,open:{[weak self] in self?.model.openPing(ping);dismiss()},dismiss:dismiss))
            cards[id]=(panel,anchor,ping,slot);panel.orderFrontRegardless()
            let preference=model.attention.preference(ping.source)
            let name=preference.character
            Diagnostics.shared.event("overlay_displayed",["app":ping.source.rawValue,"preview":ping.preview,"character":name,"slot":slot,"randomPerimeter":true,"cardStyle":"speech_bubble"])
            Diagnostics.shared.event("message_presented",["app":ping.source.rawValue,"preview":ping.preview])
            MascotDirector.shared.holdDuration=model.duration
            MascotDirector.shared.summon(named:name,at:anchor,styles:preference.styles,edges:preference.edges,calm:preference.calm) { [weak self] in self?.finish(id) }
            MascotDirector.shared.setHoverRect(frame,at:anchor)
        }
    }
    private func dismiss(_ id:UUID) {
        guard let card=cards[id] else { return }
        MascotDirector.shared.dismiss(at:card.anchor)
        NSAnimationContext.runAnimationGroup { context in context.duration=0.16;card.panel.animator().alphaValue=0 }
    }
    private func finish(_ id:UUID) {
        guard let card=cards.removeValue(forKey:id) else { return }
        card.panel.orderOut(nil)
        Diagnostics.shared.event("overlay_finished",["app":card.ping.source.rawValue,"preview":card.ping.preview])
        presentAvailable()
    }
    func removeReadNotifications(_ ids:Set<UUID>) {
        queue=queue.compactMap { original in
            guard !original.inboxIDs.isEmpty else { return original }
            var ping=original;ping.inboxIDs.subtract(ids)
            return ping.inboxIDs.isEmpty ? nil:ping
        }
        for (id,card) in Array(cards) where !card.ping.inboxIDs.isEmpty {
            var ping=card.ping;ping.inboxIDs.subtract(ids)
            cards[id]=(card.panel,card.anchor,ping,card.slot)
            if ping.inboxIDs.isEmpty { dismiss(id) }
        }
    }
    func stop() {
        stopping=true;queue.removeAll();MascotDirector.shared.stop()
        let old=cards;cards.removeAll();for card in old.values { card.panel.orderOut(nil) }
    }
}
