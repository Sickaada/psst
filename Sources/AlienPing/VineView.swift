import SwiftUI
import AlienCore

final class VineState: ObservableObject {
    @Published var enabled:Bool { didSet { defaults.set(enabled,forKey:"vineEnabled") } }
    @Published var expanded:Bool { didSet { defaults.set(expanded,forKey:"vineExpanded") } }
    private let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        enabled=defaults.object(forKey:"vineEnabled") as? Bool ?? true
        expanded=defaults.object(forKey:"vineExpanded") as? Bool ?? true
    }
}

struct VineLeaf:Shape {
    func path(in r:CGRect)->Path {
        var p=Path();p.move(to:CGPoint(x:r.minX,y:r.maxY))
        p.addCurve(to:CGPoint(x:r.maxX,y:r.minY),control1:CGPoint(x:r.minX-2,y:r.minY+2),control2:CGPoint(x:r.midX,y:r.minY-2))
        p.addCurve(to:CGPoint(x:r.minX,y:r.maxY),control1:CGPoint(x:r.maxX+2,y:r.maxY-2),control2:CGPoint(x:r.midX,y:r.maxY+2));return p
    }
}
struct VineHitTarget:Equatable { var rect:CGRect;var scrolled:Bool }
private struct VineTargets:PreferenceKey {
    static var defaultValue:[VineHitTarget]=[]
    static func reduce(value:inout [VineHitTarget],nextValue:()->[VineHitTarget]) { value+=nextValue() }
}
private extension View {
    func vineTarget(scrolled:Bool=false)->some View {
        background(GeometryReader { g in Color.clear.preference(key:VineTargets.self,value:[VineHitTarget(rect:g.frame(in:.named("vine")),scrolled:scrolled)]) })
    }
}
struct VineStem:View {
    var body:some View {
        Canvas { ctx,size in
            var stem=Path();stem.move(to:CGPoint(x:27,y:size.height+8))
            var y=size.height
            while y > -100 {
                stem.addCurve(to:CGPoint(x:27,y:y-100),control1:CGPoint(x:2,y:y-30),control2:CGPoint(x:49,y:y-75));y-=100
            }
            ctx.stroke(stem,with:.color(Color(hex:"64774F")),style:StrokeStyle(lineWidth:3.4,lineCap:.round))
            ctx.stroke(stem.offsetBy(dx:1,dy:0),with:.color(Color(hex:"B5C58A").opacity(0.75)),lineWidth:1)
            for i in 0..<Int(size.height/96) {
                let r=CGRect(x:i%2==0 ? 8:29,y:CGFloat(i)*96+24,width:17,height:25)
                ctx.fill(VineLeaf().path(in:r),with:.linearGradient(Gradient(colors:[Color(hex:"C6D39A"),Color(hex:"718A4F")]),startPoint:r.origin,endPoint:CGPoint(x:r.maxX,y:r.maxY)))
            }
        }.frame(width:52).allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct VineView:View {
    @ObservedObject var attention:AttentionController
    @ObservedObject var model:Model
    @ObservedObject var state:VineState
    var targetsChanged:([VineHitTarget])->Void = {_ in}
    private let ink=Color(hex:"403B32")
    private var unread:[InboxEntry] { attention.inbox.entries.filter{!$0.read} }
    private var isExpanded:Bool { state.expanded && !unread.isEmpty && !attention.isQuiet }
    var body:some View {
        Group {
            if isExpanded { expanded }
            else { collapsed }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .coordinateSpace(name:"vine")
        .onPreferenceChange(VineTargets.self,perform:targetsChanged)
        .font(.system(size:13,design:.rounded)).foregroundStyle(ink)
        .environment(\.colorScheme,.light)
    }
    private var expanded:some View {
        VStack(spacing:0) {
            HStack(spacing:8) {
                Button { attention.showInbox?() } label:{
                    HStack(spacing:7) { Image(systemName:"leaf.fill").foregroundStyle(Color(hex:"748354"));Text("Psst").fontWeight(.semibold);Text("\(unread.count) unread").foregroundStyle(ink.opacity(0.65)) }
                }.buttonStyle(.plain).help("Open notification tray")
                Spacer(minLength:2)
                Button { state.expanded=false } label:{Image(systemName:"chevron.left").frame(width:28,height:28)}.buttonStyle(.plain).help("Collapse vine").accessibilityLabel("Collapse notification vine")
            }.padding(.leading,12).padding(.trailing,5).frame(height:40)
                .background(Color(hex:"FFF8ED"),in:Capsule()).overlay(Capsule().strokeBorder(ink.opacity(0.1)))
                .shadow(color:.black.opacity(0.08),radius:8,y:3).vineTarget().padding(.leading,42).padding(.trailing,10).padding(.top,8).padding(.bottom,8)
            ScrollView {
                VStack(alignment:.leading,spacing:0) {
                    ForEach([SourceApp.claude,.codex]) { source in
                        let entries=unread.filter{$0.source==source}
                        if !entries.isEmpty {
                            HStack(spacing:7) {
                                Image(systemName:source == .claude ? "sun.max.fill":"terminal.fill")
                                Text(source.rawValue).fontWeight(.semibold)
                                Text("\(entries.count)").foregroundStyle(ink.opacity(0.5))
                            }.foregroundStyle(accent(source)).padding(.horizontal,12).padding(.vertical,7)
                                .background(Color(hex:"FFF8ED"),in:Capsule()).padding(.leading,45).padding(.top,12).padding(.bottom,8)
                            ForEach(entries) { entry in row(entry) }
                        }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(.bottom,15)
            }.background(alignment:.leading){ VineStem() }.scrollIndicators(.hidden)
            Button { attention.showInbox?() } label:{Text("Open tray").font(.system(size:11,weight:.medium,design:.rounded)).padding(.horizontal,14).padding(.vertical,7)}
                .buttonStyle(.plain).background(Color(hex:"FFF8ED"),in:Capsule()).vineTarget().padding(.vertical,8)
        }
    }
    private func accent(_ source:SourceApp)->Color { Color(hex:source == .claude ? "BC673D":"397EA3") }
    private func row(_ entry:InboxEntry)->some View {
        let color=accent(entry.source)
        let title=model.hideText || entry.title.isEmpty ? "Notification from \(entry.source.rawValue)" : entry.title
        return HStack(spacing:0) {
            ZStack {
                Path { p in p.move(to:CGPoint(x:22,y:42));p.addQuadCurve(to:CGPoint(x:52,y:23),control:CGPoint(x:42,y:45)) }.stroke(Color(hex:"748354"),lineWidth:2)
                VineLeaf().fill(LinearGradient(colors:[color.opacity(0.6),color],startPoint:.topTrailing,endPoint:.bottomLeading)).frame(width:22,height:29).offset(x:9,y:-5)
                Path { p in p.move(to:CGPoint(x:32,y:35));p.addLine(to:CGPoint(x:48,y:14)) }.stroke(.white.opacity(0.5),lineWidth:0.8)
            }.frame(width:52,height:68).allowsHitTesting(false).accessibilityHidden(true)
            HStack(spacing:2) {
                Button { attention.open(entry) } label:{
                    VStack(alignment:.leading,spacing:4) {
                        Text(title).font(.system(size:13,weight:.semibold,design:.rounded)).lineLimit(2).multilineTextAlignment(.leading)
                        Text(entry.date,style:.relative).font(.system(size:10)).foregroundStyle(ink.opacity(0.55))
                    }.frame(maxWidth:.infinity,minHeight:46,alignment:.leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Open \(entry.source.rawValue)")
                Button { attention.markRead(entry.id) } label:{Image(systemName:"checkmark.circle").font(.system(size:18,weight:.light)).foregroundStyle(color).frame(width:32,height:44)}
                    .buttonStyle(.plain).help("Mark read").accessibilityLabel("Mark \(title) read")
            }.padding(.leading,14).padding(.trailing,5).padding(.vertical,7)
                .background(Color(hex:entry.source == .claude ? "FFF6E9":"F0F8FF"),in:RoundedRectangle(cornerRadius:22))
                .overlay(RoundedRectangle(cornerRadius:22).strokeBorder(color.opacity(0.18)))
                .shadow(color:.black.opacity(0.07),radius:5,y:3).vineTarget(scrolled:true).padding(.trailing,12)
        }.padding(.bottom,8)
    }
    private var collapsed:some View {
        ZStack(alignment:.topLeading) {
            VineStem().frame(width:52,height:112)
            Button {
                if attention.isQuiet || unread.isEmpty { attention.showInbox?() } else { state.expanded=true }
            } label:{
                ZStack {
                    VineLeaf().fill(LinearGradient(colors:[Color(hex:"B7CD8A"),Color(hex:"64814D")],startPoint:.topTrailing,endPoint:.bottomLeading)).frame(width:38,height:48)
                    Text(unread.isEmpty ? "✓" : "\(unread.count)").font(.system(size:14,weight:.bold,design:.rounded)).foregroundStyle(.white).shadow(color:.black.opacity(0.18),radius:1).offset(y:2)
                }.frame(width:48,height:60).contentShape(Rectangle())
            }.buttonStyle(.plain).help(attention.isQuiet ? "Quiet mode · \(unread.count) unread. Open tray" : "\(unread.count) unread. Open vine")
                .accessibilityLabel("Psst, \(unread.count) unread notifications")
                .vineTarget().offset(x:20,y:23)
            if attention.isQuiet { Image(systemName:"moon.fill").font(.system(size:10)).foregroundStyle(ink).padding(5).background(Color(hex:"FFF8ED"),in:Circle()).offset(x:42,y:76).allowsHitTesting(false) }
        }.frame(width:76,height:116)
    }
}
