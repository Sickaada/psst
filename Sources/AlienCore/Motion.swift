import Foundation
import CoreGraphics

public enum ArrivalEdge: String { case left, right, top, bottom }
public struct CourierPlan {
    public var actorFrame: CGRect
    public var bubbleFrame: CGRect
    public var entry: CGPoint
    public var entryControl: CGPoint
    public var exit: CGPoint
    public var exitControl: CGPoint
    public var edge: ArrivalEdge
    public var flying: Bool
    public var entryDuration: Double
    public var exitDuration: Double
    public var holdVariation: Double
    public var mirrored: Bool { entry.x > actorFrame.minX }
    public func heading(_ t: CGFloat, departing: Bool = false) -> CGFloat {
        let a = departing ? actorFrame.origin : entry
        let b = departing ? exit : actorFrame.origin
        let c = departing ? exitControl : entryControl
        let t = min(1,max(0,t))
        let dx = 2*((1-t)*(c.x-a.x)+t*(b.x-c.x))
        let dy = 2*((1-t)*(c.y-a.y)+t*(b.y-c.y))
        return atan2(dy,max(1,abs(dx)))
    }
    public func position(_ t: CGFloat, departing: Bool = false) -> CGPoint {
        let a = departing ? actorFrame.origin : entry
        let b = departing ? exit : actorFrame.origin
        let c = departing ? exitControl : entryControl
        let t = min(1,max(0,t)), u = 1-t
        return CGPoint(x: u*u*a.x+2*u*t*c.x+t*t*b.x, y:u*u*a.y+2*u*t*c.y+t*t*b.y)
    }
    public static func make(source: SourceApp, bounds: CGRect, placement: String, seed: UInt64, perimeter: CGRect? = nil) -> CourierPlan {
        var state = seed
        func roll() -> CGFloat {
            state &+= 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            z ^= z >> 31
            return CGFloat(Double(z >> 11) / 9007199254740992.0)
        }
        let flying = source == .claude
        let safe = bounds.insetBy(dx: 16, dy: 16)
        let actorSize = min(CGFloat(64), safe.width)
        let bubbleWidth = min(CGFloat(388), safe.width)
        let bubbleHeight = min(CGFloat(144), safe.height)
        let destination = placement == "Surprise me" ? "Top right" : placement
        let gx = safe.minX + (destination.hasSuffix("right") ? 1 : 0) * max(0,safe.width-bubbleWidth)
        let gy = safe.minY + (destination.hasPrefix("Top") ? 1 : 0) * max(0,safe.height-bubbleHeight)
        let display = perimeter ?? bounds
        let edges: [ArrivalEdge] = [.left,.right,.top,.bottom]
        let edge = edges[min(edges.count-1,Int(roll()*CGFloat(edges.count)))]
        let bubbleFrame = CGRect(x:gx,y:gy,width:bubbleWidth,height:bubbleHeight)
        let actorFrame = CGRect(x:gx+12,y:gy+(bubbleHeight-actorSize)/2,width:actorSize,height:actorSize)
        func offscreen(_ edge: ArrivalEdge) -> CGPoint {
            let gap: CGFloat = 100
            switch edge {
            case .left: return CGPoint(x:display.minX-gap,y:display.minY+roll()*max(0,display.height-actorSize))
            case .right: return CGPoint(x:display.maxX+gap,y:display.minY+roll()*max(0,display.height-actorSize))
            case .top: return CGPoint(x:display.minX+roll()*max(0,display.width-actorSize),y:display.maxY+gap)
            case .bottom: return CGPoint(x:display.minX+roll()*max(0,display.width-actorSize),y:display.minY-gap)
            }
        }
        let entry = offscreen(edge)
        let exits = edges.filter { $0 != edge }
        let exitEdge = exits[min(exits.count-1,Int(roll()*CGFloat(exits.count)))]
        let exit = offscreen(exitEdge)
        // A horizontal final tangent lets the courier level out before docking.
        let facing: CGFloat = entry.x > actorFrame.minX ? 1 : -1
        let approach = CGPoint(x:actorFrame.minX+facing*min(180,bounds.width*0.25),y:actorFrame.minY)
        let departure = CGPoint(x:actorFrame.minX+(exit.x > actorFrame.minX ? 150 : -150),y:actorFrame.minY)
        let distance = hypot(entry.x-actorFrame.minX,entry.y-actorFrame.minY)
        let exitDistance = hypot(exit.x-actorFrame.minX,exit.y-actorFrame.minY)
        return CourierPlan(actorFrame:actorFrame,bubbleFrame:bubbleFrame,entry:entry,entryControl:approach,exit:exit,exitControl:departure,edge:edge,flying:flying,entryDuration:Double(min(2.2,max(0.9,distance/950+0.45))),exitDuration:Double(min(1.6,max(0.65,exitDistance/1200+0.25))),holdVariation:0)
    }
}

public struct NotificationClock {
    public private(set) var elapsed: Double = 0
    public init() {}
    public mutating func advance(by delta: Double, hovered: Bool, entrance: Double, hold: Double) {
        if hovered && elapsed >= entrance && elapsed < entrance + hold { return }
        let next = elapsed + max(0, delta)
        elapsed = hovered && elapsed < entrance ? min(next, entrance) : next
    }
}
