import AppKit
import QuartzCore
import ImageIO
import AlienCore

struct CachedAnimation {
    let spec: SpriteAnimationSpec
    let frames: [CGImage]
    func frame(at time: Double) -> CGImage { frames[spec.frameIndex(at:time)] }
}
final class SpriteLibrary {
    static let shared = SpriteLibrary()
    private(set) var manifest: MascotManifest?
    private(set) var failure: String?
    private var cache: [String:CachedAnimation] = [:]
    private(set) var sheetLoads = 0
    var characters: [MascotSpec] { manifest?.characters ?? [] }
    private init() {
        do {
            guard let base=Bundle.main.resourceURL else { throw NSError(domain:"Sprites",code:1) }
            let manifest=try JSONDecoder().decode(MascotManifest.self,from:Data(contentsOf:base.appendingPathComponent("mascots.json")))
            try manifest.validate()
            var sheets: [String:CGImage] = [:]
            func preload(_ key: String,_ spec: SpriteAnimationSpec) throws {
                for (facing,path) in spec.sheets {
                    let atlas:CGImage
                    if let existing=sheets[path] { atlas=existing }
                    else {
                        guard let source=CGImageSourceCreateWithURL(base.appendingPathComponent(path) as CFURL,nil),let decoded=CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { throw NSError(domain:"Sprites",code:2,userInfo:[NSLocalizedDescriptionKey:"Could not decode \(path)"]) }
                        atlas=decoded;sheets[path]=atlas;sheetLoads+=1
                    }
                    guard atlas.width == spec.cellWidth*spec.frameCount, atlas.height == spec.cellHeight else { throw NSError(domain:"Sprites",code:3,userInfo:[NSLocalizedDescriptionKey:"Wrong dimensions: \(path)"]) }
                    let frames=(0..<spec.frameCount).compactMap { atlas.cropping(to:CGRect(x:$0*spec.cellWidth,y:0,width:spec.cellWidth,height:spec.cellHeight)) }
                    guard frames.count == spec.frameCount else { throw NSError(domain:"Sprites",code:4) }
                    cache[key+"/"+facing]=CachedAnimation(spec:spec,frames:frames)
                }
            }
            for character in manifest.characters { for (name,spec) in character.animations { try preload(character.id+"/"+name,spec) } }
            try preload("effect",manifest.arrivalEffect)
            self.manifest=manifest
            Diagnostics.shared.event("sprite_cache_ready",["characters":characters.count,"sheetLoads":sheetLoads,"cachedAnimations":cache.count])
        } catch {
            failure=error.localizedDescription; cache.removeAll()
            Diagnostics.shared.event("sprite_cache_failed")
        }
    }
    func character(_ id: String) -> MascotSpec? { characters.first { $0.id == id.lowercased() } }
    func animation(_ id: String,_ name: String,_ facing: String) -> CachedAnimation? { cache[id+"/"+name+"/"+facing] }
    func effect(_ facing: String = "east") -> CachedAnimation? { cache["effect/"+facing] }
}

/// Sprites use positive X/Y scales only. Each facing is a separately bundled sheet.
final class SpriteMascotView: NSView {
    let sprite=CALayer(),effect=CALayer(),glow=CALayer()
    private let viewport=CAShapeLayer()
    private let spec: MascotSpec
    private var playing=""
    private let style: MascotStyle
    private(set) var observedFrames=Set<ObjectIdentifier>()
    init(character: MascotSpec,size: CGSize,style: MascotStyle = .running) {
        spec=character;self.style=style
        super.init(frame:CGRect(origin:.zero,size:size))
        wantsLayer=true;layer?.backgroundColor=NSColor.clear.cgColor
        layer?.addSublayer(glow);layer?.addSublayer(effect);layer?.addSublayer(sprite)
        layer?.mask=viewport;viewport.path=CGPath(rect:bounds,transform:nil)
        sprite.magnificationFilter = .linear;sprite.minificationFilter = .linear
        sprite.contentsGravity = .resizeAspect
        effect.contentsGravity = .resizeAspect
        glow.backgroundColor=(character.motionClass == "jet" ? NSColor.systemOrange : NSColor.systemCyan).cgColor
        glow.shadowColor=glow.backgroundColor;glow.shadowRadius=8;glow.shadowOpacity=0.8
        setAccessibilityElement(true);setAccessibilityRole(.image);setAccessibilityLabel(character.name+" animated notification companion")
    }
    required init?(coder:NSCoder) { nil }
    func show(_ sample: MascotSample,reduced: Bool = false) {
        if let displayed=sprite.presentation()?.contents { observedFrames.insert(ObjectIdentifier(displayed as AnyObject)) }
        let phase=sample.phase == .finished ? "exit" : sample.phase.rawValue
        let animationName = phase == "travel" ? style.rawValue : phase
        guard let animation=SpriteLibrary.shared.animation(spec.id,animationName,sample.facing) ?? SpriteLibrary.shared.animation(spec.id,phase,sample.facing) else { return }
        CATransaction.begin();CATransaction.setDisableActions(true)
        let aspect=CGFloat(animation.spec.cellWidth)/CGFloat(animation.spec.cellHeight)
        let h=sample.size*1.25,w=h*aspect
        sprite.frame=CGRect(x:bounds.midX-w*spec.pivot.x,y:bounds.midY-h*spec.pivot.y,width:w,height:h)
        let key=phase+"/"+sample.facing+(reduced ? "/still" : "")
        if key != playing {
            sprite.removeAnimation(forKey:"frames")
            sprite.contents=animation.frame(at:0)
            if !reduced {
                let step=CAKeyframeAnimation(keyPath:"contents")
                step.values=animation.spec.sequence.map { animation.frames[$0] }
                step.keyTimes=(0..<animation.spec.sequence.count).map { NSNumber(value:Double($0)/Double(animation.spec.sequence.count)) }
                step.calculationMode = .discrete;step.duration=animation.spec.duration;step.repeatCount = animation.spec.loop ? .infinity : 1;step.fillMode = .forwards;step.isRemovedOnCompletion=false
                step.beginTime=CACurrentMediaTime()-sample.phaseTime
                sprite.add(step,forKey:"frames")
            }
            playing=key
        }
        if spec.motionClass == "magic", let t=sample.effectTime,let fx=SpriteLibrary.shared.effect() {
            effect.isHidden=false;effect.contents=fx.frame(at:t)
            effect.frame=CGRect(x:bounds.midX-52,y:bounds.midY-48,width:104,height:104)
        } else { effect.isHidden=true }
        // Small propulsion glows complement actual changing jump/fall silhouettes.
        if style == .portal && sample.phase == .travel && !reduced {
            effect.isHidden=false;effect.contents=nil
            effect.frame=CGRect(x:bounds.midX-h*0.4,y:bounds.midY-h*0.48,width:h*0.8,height:h*0.96)
            effect.cornerRadius=h*0.4;effect.borderWidth=2
            effect.borderColor=(spec.id == "sunburst" ? NSColor.systemOrange : NSColor.systemPurple).cgColor
            effect.shadowColor=effect.borderColor;effect.shadowOpacity=0.8;effect.shadowRadius=7
            effect.opacity=Float(max(0,1-sample.phaseTime/2.65))
        } else { effect.borderWidth=0;effect.shadowOpacity=0;effect.opacity=1 }
        let travel=sample.phase == .travel || sample.phase == .exit
        glow.isHidden=reduced || !travel || !["jet","magic"].contains(spec.motionClass)
        let pulse=CGFloat(0.7+0.3*sin(sample.phaseTime*27))
        glow.opacity=Float(pulse*0.7)
        glow.frame=CGRect(x:bounds.midX-7,y:bounds.midY-h*0.48-6,width:14,height:12+8*pulse)
        glow.cornerRadius=7
        CATransaction.commit()
    }
    func clip(_ rect: CGRect) { CATransaction.begin();CATransaction.setDisableActions(true);viewport.path=CGPath(rect:rect,transform:nil);CATransaction.commit() }
}
