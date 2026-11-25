import AppKit
import SwiftUI
import Combine
import AlienCore

/// A nonactivating accessory; decorative space never owns the mouse.
final class VineController {
    let state:VineState
    private var presenting=true
    private let model:Model
    private var panel:NSPanel?
    private var subscriptions=Set<AnyCancellable>()
    private var targets:[VineHitTarget]=[]
    private var timer:Timer?
    private var globalMouse:Any?
    private var localMouse:Any?
    private var lastLayout=""
    init(model:Model,state:VineState=VineState()) { self.model=model;self.state=state }
    func start(present:Bool=true) {
        presenting=present
        let p=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.level = .floating
        p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false;p.becomesKeyOnlyIfNeeded=true
        p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
        p.isMovable=false;p.acceptsMouseMovedEvents=true;p.ignoresMouseEvents=true
        p.contentView=NSHostingView(rootView:VineView(attention:model.attention,model:model,state:state,targetsChanged:{ [weak self] frames in self?.targets=frames;self?.updateMouse() }))
        panel=p
        for publisher in [state.objectWillChange.eraseToAnyPublisher(),model.attention.objectWillChange.eraseToAnyPublisher()] {
            publisher.receive(on:DispatchQueue.main).sink { [weak self] in self?.layout() }.store(in:&subscriptions)
        }
        NotificationCenter.default.publisher(for:NSApplication.didChangeScreenParametersNotification).receive(on:DispatchQueue.main).sink { [weak self] _ in self?.layout() }.store(in:&subscriptions)
        globalMouse=NSEvent.addGlobalMonitorForEvents(matching:[.mouseMoved,.leftMouseDragged,.rightMouseDragged]) { [weak self] _ in self?.updateMouse() }
        localMouse=NSEvent.addLocalMonitorForEvents(matching:[.mouseMoved,.leftMouseDown,.scrollWheel]) { [weak self] event in self?.updateMouse();return event }
        timer=Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { [weak self] _ in self?.layout();self?.updateMouse() }
        layout()
    }
    func toggle() { state.enabled.toggle() }
    func stop() {
        timer?.invalidate();timer=nil;subscriptions.removeAll()
        if let globalMouse { NSEvent.removeMonitor(globalMouse) };globalMouse=nil
        if let localMouse { NSEvent.removeMonitor(localMouse) };localMouse=nil
        panel?.orderOut(nil);panel=nil
    }
    private func layout() {
        guard let panel,let screen=NSScreen.screens.first else { return }
        guard state.enabled else { panel.orderOut(nil);return }
        let count=VineSummary.previewable(model.attention.inbox.entries).count
        let expanded=state.expanded && count>0 && !model.attention.isQuiet
        let area=screen.visibleFrame
        let height=expanded ? area.height-24 : 116
        let width:CGFloat=expanded ? min(372,area.width) : 76
        let rect=NSRect(x:area.minX+4,y:area.midY-height/2,width:width,height:height)
        if panel.frame != rect { panel.setFrame(rect,display:true) }
        if presenting && !panel.isVisible {
            panel.alphaValue=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1:0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0:0.28
                panel.animator().alphaValue=1
            }
        }
        let key="\(expanded)-\(count)-\(Int(area.width))-\(Int(area.height))"
        if key != lastLayout {
            lastLayout=key
            Diagnostics.shared.event("vine_layout",["expanded":expanded,"unread":count,"width":width,"height":height,"quiet":model.attention.isQuiet])
        }
    }
    func renderOffscreenForVerification() {
        guard !presenting,let host=panel?.contentView else { return }
        host.layoutSubtreeIfNeeded()
        if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) { host.cacheDisplay(in:host.bounds,to:bitmap) }
    }
    // Exposes layout evidence for the offscreen regression harness; never captures a screen.
    var layoutEvidence:(frame:CGRect,targets:[CGRect]) { (panel?.frame ?? .zero,visibleTargets) }
    private var visibleTargets:[CGRect] {
        guard let panel else { return [] }
        let bounds=CGRect(origin:.zero,size:panel.frame.size)
        // Expanded header is 56pt and footer is 44pt; rows must stay inside the scroll viewport.
        let viewport=CGRect(x:0,y:56,width:bounds.width,height:max(0,bounds.height-100))
        return targets.map { $0.rect.intersection($0.scrolled ? viewport : bounds) }.filter{!$0.isNull && !$0.isEmpty}
    }
    private func updateMouse() {
        guard let panel else { return }
        let mouse=NSEvent.mouseLocation
        let point=CGPoint(x:mouse.x-panel.frame.minX,y:panel.frame.maxY-mouse.y)
        let bounds=CGRect(origin:.zero,size:panel.frame.size)
        let interactive=state.enabled && panel.isVisible && bounds.contains(point) && visibleTargets.contains { $0.contains(point) }
        panel.ignoresMouseEvents = !interactive
    }
}
