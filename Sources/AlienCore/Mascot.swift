import Foundation
import CoreGraphics

public struct SpritePivot: Codable { public let x: Double; public let y: Double }
public struct SpriteAnimationSpec: Codable {
    public let sheets: [String:String]
    public let cellWidth: Int
    public let cellHeight: Int
    public let frameCount: Int
    public let fps: Double
    public let sequence: [Int]
    public let loop: Bool
    public var duration: Double { Double(sequence.count)/fps }
    public func frameIndex(at time: Double) -> Int {
        let step = max(0,Int(max(0,time)*fps))
        return sequence[loop ? step % sequence.count : min(step,sequence.count-1)]
    }
}
public struct MascotSpec: Codable {
    public let id: String
    public let name: String
    public let motionClass: String
    public let pivot: SpritePivot
    public let animations: [String:SpriteAnimationSpec]
}
public struct MascotManifest: Codable {
    public let version: Int
    public let characters: [MascotSpec]
    public let arrivalEffect: SpriteAnimationSpec
    public func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain:"MascotManifest",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        }
        try require(version == 1 && !characters.isEmpty,"Unsupported or empty manifest")
        try require(Set(characters.map(\.id)).count == characters.count,"Duplicate character IDs")
        for c in characters {
            try require((0...1).contains(c.pivot.x) && (0...1).contains(c.pivot.y),"Invalid pivot")
            for phase in ["travel","idle","exit"] { try require(c.animations[phase] != nil,"Missing phase: \(phase)") }
        }
        for a in characters.flatMap({Array($0.animations.values)}) + [arrivalEffect] {
            try require(a.cellWidth > 0 && a.cellHeight > 0 && a.frameCount > 0 && a.frameCount <= 256,"Invalid cells")
            try require(a.fps > 0 && a.fps <= 120 && !a.sequence.isEmpty,"Invalid frame timing")
            try require(a.sequence.allSatisfy { $0 >= 0 && $0 < a.frameCount },"Out-of-range frame")
            try require(a.sheets["east"] != nil && a.sheets["west"] != nil,"Missing facing")
            try require(a.sheets.values.allSatisfy { !$0.hasPrefix("/") && !$0.split(separator:"/").contains("..") },"Unsafe resource path")
        }
    }
}

public enum MascotStyle: String, CaseIterable, Codable { case running, chasing, parkour, delivery, portal, peekaboo, celebration, floating }
public struct MascotStyleBag {
    private var bag:[MascotStyle]=[]
    private var previous:MascotStyle?
    public init() {}
    private var allowed:[MascotStyle]=MascotStyle.allCases
    public mutating func next(styles:[MascotStyle]=MascotStyle.allCases) -> MascotStyle {
        let choices=MascotStyle.allCases.filter{styles.contains($0)}
        let valid=choices.isEmpty ? MascotStyle.allCases : choices
        if valid != allowed { allowed=valid;bag=[] }
        if bag.isEmpty {
            bag=allowed.shuffled()
            if bag.last == previous { bag.swapAt(0,bag.count-1) }
        }
        let value=bag.removeLast();previous=value;return value
    }
}

public enum MascotPhase: String { case travel, idle, exit, finished }
public struct MascotSample {
    public let phase: MascotPhase
    public let phaseTime: Double
    public let position: CGPoint
    public let size: CGFloat
    public let opacity: CGFloat
    public let facing: String
    public let effectTime: Double?
}
public struct MascotFlight {
    public let style: MascotStyle
    private let bounds: CGRect
    public let start: CGPoint
    public let anchor: CGPoint
    public let end: CGPoint
    public let control: CGPoint
    public let entrance: Double
    public let hold: Double
    public let departure: Double = 0.8
    public var duration: Double { entrance + hold + departure }
    public init(bounds: CGRect, anchor requested: CGPoint, seed: UInt64, hold: Double = 2.4, style: MascotStyle = .running, edges:[ScreenEdge]=ScreenEdge.allCases) {
        self.style=style;self.bounds=bounds
        let safe = bounds.insetBy(dx:min(60,bounds.width/4),dy:min(60,bounds.height/4))
        anchor = CGPoint(x:min(safe.maxX,max(safe.minX,requested.x)),y:min(safe.maxY,max(safe.minY,requested.y)))
        var rng=seed
        func roll() -> CGFloat { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(Double(rng >> 11)/9007199254740992.0) }
        let edge=bounds
        let allowed=ScreenEdge.allCases.filter{edges.contains($0)}
        let choices=allowed.isEmpty ? ScreenEdge.allCases : allowed
        let selected=choices[min(choices.count-1,Int(roll()*CGFloat(choices.count)))],along=roll()
        switch selected {
        case .left:start=CGPoint(x:edge.minX,y:edge.minY+along*edge.height)
        case .right:start=CGPoint(x:edge.maxX,y:edge.minY+along*edge.height)
        case .top:start=CGPoint(x:edge.minX+along*edge.width,y:edge.maxY)
        case .bottom:start=CGPoint(x:edge.minX+along*edge.width,y:edge.minY)
        }
        let away: CGFloat = start.x > anchor.x ? 1 : -1
        control=CGPoint(x:min(safe.maxX,max(safe.minX,anchor.x+away*min(150,safe.width/3))),y:anchor.y)
        end=CGPoint(x:start.x > safe.midX ? safe.minX : safe.maxX,y:safe.minY+roll()*safe.height)
        entrance=2.65
        self.hold=max(0.2,hold)
    }
    public func sample(at time: Double, reduced: Bool = false) -> MascotSample {
        let t=max(0,time)
        let facing=start.x > anchor.x ? "west" : "east"
        if t < entrance {
            let u=CGFloat(t/entrance),v=1-pow(1-u,3)
            var p=CGPoint(x:pow(1-v,2)*start.x+2*(1-v)*v*control.x+v*v*anchor.x,y:pow(1-v,2)*start.y+2*(1-v)*v*control.y+v*v*anchor.y)
            let envelope=sin(u * .pi)
            switch style {
            case .running: p.y += abs(sin(u * .pi * 9))*5*envelope
            case .chasing: p.x += sin(u * .pi * 4)*32*envelope;p.y += cos(u * .pi * 4)*20*envelope
            case .parkour: p.y += 90*envelope
            case .delivery: p.y += sin(u * .pi * 2)*8*envelope
            case .portal: p.x += sin(u * .pi * 2)*18*envelope
            case .peekaboo: p.y -= 30*envelope
            case .celebration: p.y += abs(sin(u * .pi * 3))*48*envelope
            case .floating: p.y += sin(u * .pi * 3)*22*envelope
            }
            p.x=min(bounds.maxX,max(bounds.minX,p.x));p.y=min(bounds.maxY,max(bounds.minY,p.y))
            return MascotSample(phase:.travel,phaseTime:t,position:reduced ? anchor : p,size:reduced ? 64 : 64+40*pow(1-u,2),opacity:min(1,u*8),facing:facing,effectTime:nil)
        }
        if t < entrance+hold {
            let idle=t-entrance
            let p=CGPoint(x:anchor.x,y:anchor.y+(reduced ? 0 : sin(idle*2.2)*1.2))
            return MascotSample(phase:.idle,phaseTime:idle,position:p,size:reduced ? 64 : 64+sin(idle*2.2)*0.5,opacity:1,facing:facing,effectTime:idle < 2.0/3.0 && !reduced ? idle : nil)
        }
        let u=t >= duration ? 1 : min(1,(t-entrance-hold)/departure),v=CGFloat(u*u)
        return MascotSample(phase:u >= 1 ? .finished : .exit,phaseTime:t-entrance-hold,position:reduced ? anchor : CGPoint(x:anchor.x+(end.x-anchor.x)*v,y:anchor.y+(end.y-anchor.y)*v),size:reduced ? 64 : 64+40*CGFloat(u),opacity:CGFloat(1-u),facing:end.x < anchor.x ? "west" : "east",effectTime:nil)
    }
}
