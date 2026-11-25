import AppKit
import QuartzCore
import AlienCore

final class MascotStageCanvas:NSView {
    private var actor:SpriteMascotView?
    private var timer:Timer?
    private var began:CFTimeInterval=0
    private var flight:MascotFlight?
    private var name="terminal"
    private var styles=MascotStyleBag()
    private var then:(()->Void)?
    var card:CGRect { CGRect(x:bounds.maxX-400,y:bounds.midY-72,width:388,height:144) }
    override init(frame:NSRect) { super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=NSColor.clear.cgColor }
    required init?(coder:NSCoder) { nil }
    override func draw(_ dirtyRect:NSRect) {
        NSColor(calibratedRed:0.10,green:0.12,blue:0.16,alpha:1).setFill();NSBezierPath(roundedRect:card,xRadius:16,yRadius:16).fill()
        let title="\(name.capitalized) · Sprite preview"
        title.draw(at:CGPoint(x:card.minX+88,y:card.maxY-38),withAttributes:[.font:NSFont.systemFont(ofSize:15,weight:.semibold),.foregroundColor:NSColor.white])
        "104 px in flight → 64 px docked".draw(at:CGPoint(x:card.minX+88,y:card.midY-5),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.lightGray])
        "Eight random styles · screen-edge entrances".draw(at:CGPoint(x:card.minX+88,y:card.minY+28),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.systemCyan])
    }
    func play(_ name:String,then:(()->Void)?=nil) {
        timer?.invalidate();actor?.removeFromSuperview();self.then=then
        guard let spec=SpriteLibrary.shared.character(name) else { return }
        self.name=name;needsDisplay=true
        let style=styles.next()
        let view=SpriteMascotView(character:spec,size:CGSize(width:160,height:160),style:style);addSubview(view);actor=view
        flight=MascotFlight(bounds:bounds,anchor:CGPoint(x:card.minX+44,y:card.midY),seed:UInt64.random(in:1...UInt64.max),hold:2.4,style:style)
        began=CACurrentMediaTime()
        Diagnostics.shared.event("mascot_stage_started",["character":name,"sheetLoads":SpriteLibrary.shared.sheetLoads])
        let timer=Timer(timeInterval:1.0/60,repeats:true){[weak self] _ in self?.tick()};self.timer=timer;RunLoop.main.add(timer,forMode:.common);tick()
    }
    private func tick() {
        guard let flight,let actor else { return }
        let sample=flight.sample(at:CACurrentMediaTime()-began,reduced:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        actor.frame.origin=CGPoint(x:sample.position.x-80,y:sample.position.y-80);actor.alphaValue=sample.opacity;actor.show(sample,reduced:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if sample.phase == .finished {
            timer?.invalidate();timer=nil
            Diagnostics.shared.event("mascot_stage_completed",["character":name,"sheetLoads":SpriteLibrary.shared.sheetLoads,"observedSpriteFrames":actor.observedFrames.count])
            let callback=then;then=nil;callback?()
        }
    }
    func stop() { timer?.invalidate();timer=nil;then=nil }
}
final class MascotStageController:NSWindowController,NSWindowDelegate {
    private let canvas=MascotStageCanvas(frame:NSRect(x:0,y:0,width:760,height:380))
    init() {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:450),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="Psst · Mascot Stage";window.backgroundColor = .clear;window.isOpaque=false;window.isReleasedWhenClosed=false
        super.init(window:window);window.delegate=self
        let content=NSView(frame:NSRect(x:0,y:0,width:760,height:450));window.contentView=content;content.addSubview(canvas)
        let items:[(String,Selector)]=[("Replay Codex",#selector(riff)),("Replay Claude",#selector(tavi)),("Play both",#selector(both))]
        for (i,item) in items.enumerated() {
            let button=NSButton(title:item.0,target:self,action:item.1);button.bezelStyle = .rounded;button.frame=NSRect(x:20+i*135,y:398,width:125,height:30);content.addSubview(button)
        }
        let label=NSTextField(labelWithString:"Sprite preview · no screen capture");label.frame=NSRect(x:430,y:404,width:300,height:20);content.addSubview(label)
        window.center()
    }
    required init?(coder:NSCoder) { nil }
    @objc func riff() { canvas.play("terminal") }
    @objc func tavi() { canvas.play("sunburst") }
    @objc func both() { canvas.play("terminal"){[weak self] in self?.canvas.play("sunburst")} }
    func present() { showWindow(nil);window?.makeKeyAndOrderFront(nil);both() }
    func windowWillClose(_ notification:Notification) { canvas.stop() }
}
