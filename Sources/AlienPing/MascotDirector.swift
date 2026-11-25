import AppKit
import QuartzCore
import AlienCore

/// The single notification integration entry point. Main-thread only.
func summonMascot(named: String, at anchor: CGPoint, completion: (() -> Void)?) {
    MascotDirector.shared.summon(named:named,at:anchor,completion:completion)
}

final class MascotDirector {
    static let shared=MascotDirector()
    var holdDuration: Double = 7
    private var timer:Timer?
    private var lastStart:CFTimeInterval = 0
    private var sessions:[UUID:Session]=[:]
    private var nextCharacter=0
    private var styleBag=MascotStyleBag()
    final class Session {
        let id=UUID(),requested:CGPoint,flight:MascotFlight,panel:NSPanel,view:SpriteMascotView,character:String,bounds:CGRect
        var calm=false
        let start:CFTimeInterval,completion:(()->Void)?
        var clock=NotificationClock(),lastTick:CFTimeInterval,hoverRect:CGRect?,fadeStarted:CFTimeInterval?,fadeAlpha:CGFloat=1,presented=false
        init(requested:CGPoint,flight:MascotFlight,panel:NSPanel,view:SpriteMascotView,character:String,bounds:CGRect,start:CFTimeInterval,completion:(()->Void)?) {
            self.requested=requested;self.flight=flight;self.panel=panel;self.view=view;self.character=character;self.bounds=bounds;self.start=start;lastTick=start;self.completion=completion
        }
    }
    func rotatingName() -> String {
        let names=SpriteLibrary.shared.characters.map(\.id)
        guard !names.isEmpty else { return "riff" }
        defer { nextCharacter+=1 };return names[nextCharacter % names.count]
    }
    func summon(named:String,at anchor:CGPoint,styles:[MascotStyle]=MascotStyle.allCases,edges:[ScreenEdge]=ScreenEdge.allCases,calm:Bool=false,completion:(()->Void)?) {
        precondition(Thread.isMainThread)
        guard let screen=NSScreen.main ?? NSScreen.screens.first,let spec=SpriteLibrary.shared.character(named) else {
            Diagnostics.shared.event("mascot_unavailable");completion?();return
        }
        let bounds=screen.visibleFrame
        var dock=anchor
        // Other callers can summon simultaneous mascots at the same anchor.
        for _ in 0..<sessions.count+1 {
            guard sessions.values.contains(where:{hypot($0.flight.anchor.x-dock.x,$0.flight.anchor.y-dock.y)<72}) else { break }
            dock.y -= 76
            if dock.y < bounds.minY+60 { dock.y=bounds.maxY-60;dock.x-=80 }
        }
        let style=styleBag.next(styles:styles)
        let flight=MascotFlight(bounds:bounds,anchor:dock,seed:UInt64.random(in:1...UInt64.max),hold:holdDuration,style:style,edges:edges)
        let panel=NSPanel(contentRect:CGRect(x:0,y:0,width:160,height:160),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false;panel.level = .floating
        panel.ignoresMouseEvents=true;panel.hidesOnDeactivate=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.transient]
        let view=SpriteMascotView(character:spec,size:panel.frame.size,style:style);panel.contentView=view;panel.alphaValue=0
        let now=CACurrentMediaTime(),start=max(now,lastStart+0.75);lastStart=start
        let session=Session(requested:anchor,flight:flight,panel:panel,view:view,character:spec.id,bounds:bounds,start:start,completion:completion)
        session.calm=calm
        sessions[session.id]=session
        panel.orderFrontRegardless()
        Diagnostics.shared.event("mascot_summoned",["character":spec.id,"delay":start-now,"style":style.rawValue,"startX":flight.start.x,"startY":flight.start.y,"spriteSheetLoads":SpriteLibrary.shared.sheetLoads])
        if timer == nil {
            let timer=Timer(timeInterval:1.0/60,repeats:true){[weak self] _ in self?.tick()};timer.tolerance=0.002;self.timer=timer;RunLoop.main.add(timer,forMode:.common)
        }
    }
    func setHoverRect(_ rect:CGRect,at anchor:CGPoint) { sessions.values.filter{$0.requested == anchor}.forEach{$0.hoverRect=rect} }
    func dismiss(at anchor:CGPoint) {
        for s in sessions.values where s.requested == anchor && s.fadeStarted == nil { s.fadeStarted=CACurrentMediaTime();s.fadeAlpha=s.panel.alphaValue }
    }
    func stop() { let old=Array(sessions.values);sessions.removeAll();timer?.invalidate();timer=nil;old.forEach{$0.panel.orderOut(nil)} }
    private func tick() {
        let now=CACurrentMediaTime(),reduced=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var finished:[UUID]=[]
        for (id,s) in sessions {
            if let fade=s.fadeStarted {
                let t=min(1,(now-fade)/0.16);s.panel.alphaValue=s.fadeAlpha*(1-t)
                if t >= 1 { finished.append(id) };continue
            }
            guard now >= s.start else { continue }
            let hovered=s.hoverRect.map { NSMouseInRect(NSEvent.mouseLocation,$0,false) } ?? false
            s.clock.advance(by:now-s.lastTick,hovered:hovered,entrance:s.flight.entrance,hold:s.flight.hold);s.lastTick=now
            let sample=s.flight.sample(at:s.clock.elapsed,reduced:reduced || s.calm)
            if sample.phase == .finished { finished.append(id);continue }
            let origin=CGPoint(x:sample.position.x-80,y:sample.position.y-80)
            s.panel.setFrameOrigin(origin);s.panel.alphaValue=sample.opacity
            s.view.show(sample,reduced:reduced || s.calm)
            let visible=CGRect(origin:origin,size:s.panel.frame.size).intersection(s.bounds)
            s.view.clip(visible.isNull ? .zero : visible.offsetBy(dx:-origin.x,dy:-origin.y))
            if sample.phase == .idle && !s.presented { s.presented=true;Diagnostics.shared.event("mascot_docked",["character":s.character,"spriteSheetLoads":SpriteLibrary.shared.sheetLoads]) }
        }
        for id in finished { if let s=sessions.removeValue(forKey:id) { s.panel.orderOut(nil);s.completion?();Diagnostics.shared.event("mascot_finished",["character":s.character]) } }
        if sessions.isEmpty { timer?.invalidate();timer=nil }
    }
}
