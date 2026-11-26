import SwiftUI
import AlienCore

final class VineState: ObservableObject {
    @Published var enabled:Bool { didSet { defaults.set(enabled,forKey:"vineEnabled") } }
    @Published var expanded:Bool { didSet { defaults.set(expanded,forKey:"vineExpanded") } }
    @Published var manuallyExpanded=false
    func visible(hasItems:Bool,quiet:Bool)->Bool { expanded && (manuallyExpanded || (hasItems && !quiet)) }
    func toggle(hasItems:Bool,quiet:Bool) {
        let next = !visible(hasItems:hasItems,quiet:quiet)
        manuallyExpanded=next;expanded=next
    }
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
    private static let artwork:NSImage? = {
        let url=Bundle.main.url(forResource:"vine-botanical",withExtension:"png") ?? URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/vine-botanical.png")
        return NSImage(contentsOf:url)
    }()
    var body:some View {
        GeometryReader { space in
            if let image=Self.artwork {
                Image(nsImage:image).resizable().interpolation(.high)
                    .frame(width:space.size.height*image.size.width/image.size.height,height:space.size.height)
                    .position(x:26,y:space.size.height/2)
            } else {
                Path { p in p.move(to:CGPoint(x:26,y:0));p.addCurve(to:CGPoint(x:26,y:space.size.height),control1:CGPoint(x:4,y:space.size.height/3),control2:CGPoint(x:48,y:space.size.height*2/3)) }.stroke(Color(hex:"829173"),lineWidth:1.5)
            }
        }.frame(width:52).allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct VineView:View {
    @ObservedObject var attention:AttentionController
    @ObservedObject var model:Model
    @ObservedObject var state:VineState
    var targetsChanged:([VineHitTarget])->Void = {_ in}
    @Environment(\.colorScheme) private var scheme
    private var ink:Color { Color(hex:scheme == .dark ? "E5ECE4":"303730") }
    private var chrome:Color { Color(hex:scheme == .dark ? "253029":"FAFCF7") }
    private var leafInk:Color { Color(hex:scheme == .dark ? "BDD1AB":"536B43") }
    private var unread:[InboxEntry] { VineSummary.previewable(attention.inbox.entries) }
    private var timeline:[InboxEntry] { VineSummary.timeline(attention.inbox.entries) }
    private var shownCount:Int { timeline.count }
    private var isExpanded:Bool { state.visible(hasItems:!unread.isEmpty,quiet:attention.isQuiet) }
    var body:some View {
        Group {
            if isExpanded { expanded }
            else { collapsed }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .overlay(alignment:.leading) { compactControl.vineTarget() }
        .coordinateSpace(name:"vine")
        .onPreferenceChange(VineTargets.self,perform:targetsChanged)
        .font(.system(size:13)).foregroundStyle(ink)
    }
    private var expanded:some View {
        VStack(spacing:0) {
            HStack(spacing:8) {
                Button { attention.showInbox?() } label:{
                    HStack(spacing:8) {
                        Image(systemName:"leaf").font(.system(size:13,weight:.medium)).foregroundStyle(leafInk)
                        Text("Notifications").font(.system(size:16,weight:.medium))
                        Text("\(shownCount) shown").font(.system(size:13)).foregroundStyle(ink.opacity(0.65))
                    }
                }.buttonStyle(.plain).help("Open notification tray")
                Spacer(minLength:2)
            }.padding(.leading,12).padding(.trailing,5).frame(height:40)
                .background(chrome,in:RoundedRectangle(cornerRadius:12))
                .shadow(color:.black.opacity(0.08),radius:8,y:2).vineTarget().padding(.leading,42).padding(.trailing,10).padding(.top,8).padding(.bottom,8)
            GeometryReader { viewport in
                ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment:.leading,spacing:0) {
                        if unread.isEmpty {
                            VStack(alignment:.leading,spacing:8) {
                                Text(attention.inbox.unreadCount == 0 ? "You’re caught up" : "No unread previews").font(.system(size:15,weight:.medium))
                                Text(attention.inbox.unreadCount == 0 ? "New unread notifications will appear here." : "Unread alerts without saved text are in your tray.").font(.system(size:15)).foregroundStyle(ink.opacity(0.7))
                            }.padding(18).background(chrome,in:RoundedRectangle(cornerRadius:14)).padding(.leading,56).padding(.trailing,12)
                        }
                        if unread.count > shownCount {
                            Button("\(unread.count - shownCount) older in tray") { attention.showInbox?() }
                                .buttonStyle(.link).vineTarget(scrolled:true).padding(.leading,66)
                        }
                        ForEach(timeline) { entry in
                            row(entry, latest:entry.id == timeline.last?.id).id(entry.id)
                        }
                    }.padding(.vertical,8).frame(maxWidth:.infinity,minHeight:viewport.size.height,alignment:unread.isEmpty ? .topLeading : .bottomLeading)
                }.scrollIndicators(.automatic)
                    .onChange(of:timeline.last?.id,initial:true) { _, id in
                        if let id { scroll.scrollTo(id,anchor:.bottom) }
                    }
                }
            }.background(alignment:.leading){ VineStem() }
            Button { attention.showInbox?() } label:{Text("View tray · \(attention.inbox.unreadCount) unread").font(.system(size:13,weight:.medium)).padding(.horizontal,14).padding(.vertical,7)}
                .buttonStyle(.plain).background(chrome,in:Capsule()).vineTarget().padding(.vertical,8)
        }
    }
    private func row(_ entry:InboxEntry, latest:Bool)->some View {
        let appearance=NotificationAppearance(source:entry.source,scheme:scheme)
        let color=appearance.accent
        let subject=entry.title.trimmingCharacters(in:.whitespacesAndNewlines)
        let title=model.hideText || subject.isEmpty ? "Notification from \(entry.source.rawValue)" : subject
        let detail=model.hideText ? "Message preview hidden" : entry.body.trimmingCharacters(in:.whitespacesAndNewlines)
        return HStack(spacing:0) {
            ZStack {
                Path { p in p.move(to:CGPoint(x:24,y:40));p.addQuadCurve(to:CGPoint(x:52,y:30),control:CGPoint(x:36,y:40)) }.stroke(Color(hex:"829173"),lineWidth:1.2)
                VineLeaf().fill(color.opacity(0.75)).frame(width:12,height:20).offset(x:8,y:-1)
            }.frame(width:52,height:68).allowsHitTesting(false).accessibilityHidden(true)
            HStack(spacing:2) {
                Button { attention.open(entry) } label:{
                    VStack(alignment:.leading,spacing:5) {
                        Text(title).font(latest ? NotificationAppearance.title : .system(size:19,weight:.medium)).tracking(-0.2).foregroundStyle(appearance.ink).lineLimit(2).multilineTextAlignment(.leading)
                        if !detail.isEmpty { Text(detail).font(NotificationAppearance.body).foregroundStyle(appearance.ink.opacity(0.88)).lineLimit(latest ? 4 : 2).multilineTextAlignment(.leading) }
                        HStack {
                            Text(entry.date.formatted(date:Calendar.current.isDateInToday(entry.date) ? .omitted : .abbreviated,time:.shortened)).monospacedDigit().foregroundStyle(appearance.secondary)
                            Spacer()
                            Text(entry.source.rawValue).font(.system(size:12,weight:.semibold)).foregroundStyle(color)
                        }.font(.system(size:12))
                    }.frame(maxWidth:.infinity,minHeight:46,alignment:.leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Open \(entry.source.rawValue)")
                Button { attention.markRead(entry.id) } label:{Image(systemName:"checkmark.circle").font(.system(size:16,weight:.regular)).foregroundStyle(color.opacity(0.8)).frame(width:30,height:44)}
                    .buttonStyle(.plain).help("Mark read").accessibilityLabel("Mark \(title) read")
            }.padding(.leading,27).padding(.trailing,8).padding(.vertical,14)
                .background(NotificationBubble().fill(appearance.paper))
                .overlay(NotificationBubble().stroke(appearance.edge.opacity(0.8),lineWidth:1).allowsHitTesting(false))
                .shadow(color:appearance.shadow,radius:4,y:2).vineTarget(scrolled:true).padding(.trailing,12)
        }.padding(.bottom,8).modifier(VineArrival())
    }
    private var collapsed:some View {
        VineStem().frame(width:52,height:116).accessibilityHidden(true)
    }
    private var compactControl:some View {
        Button {
            state.toggle(hasItems:!unread.isEmpty,quiet:attention.isQuiet)
        } label:{
            VStack(spacing:5) {
                Image(systemName:attention.isQuiet ? "moon":"chevron.\(isExpanded ? "left":"right")").font(.system(size:18,weight:.semibold))
                if !isExpanded && !unread.isEmpty { Text("\(shownCount)").font(.system(size:13,weight:.semibold)) }
                if unread.isEmpty { Image(systemName:"leaf").font(.system(size:12)) }
            }.foregroundStyle(leafInk).frame(width:52,height:64)
                .background(chrome,in:RoundedRectangle(cornerRadius:18))
                .shadow(color:.black.opacity(0.14),radius:8,y:3).contentShape(RoundedRectangle(cornerRadius:18))
        }.buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse notification vine" : "Expand notification vine")
            .help(isExpanded ? "Collapse notifications" : "Open notifications")
    }

}

// Only a newly inserted row fades; existing rows never bounce or replay their entrance.
private struct VineReducedPreviewKey:EnvironmentKey { static let defaultValue=false }
private struct VineStaticPreviewKey:EnvironmentKey { static let defaultValue=false }
extension EnvironmentValues {
    var vineReducedPreview:Bool {
        get { self[VineReducedPreviewKey.self] }
        set { self[VineReducedPreviewKey.self]=newValue }
    }
    var vineStaticPreview:Bool {
        get { self[VineStaticPreviewKey.self] }
        set { self[VineStaticPreviewKey.self]=newValue }
    }
}
private final class VineFadeClock:ObservableObject {
    @Published var opacity:Double=0
    private var timer:Timer?
    private var started=false
    func start(immediate:Bool) {
        guard !started else { return };started=true
        if immediate { opacity=1;return }
        let start=ProcessInfo.processInfo.systemUptime
        timer=Timer.scheduledTimer(withTimeInterval:1.0/60,repeats:true) { [weak self] timer in
            guard let self else { timer.invalidate();return }
            let progress=min(1,(ProcessInfo.processInfo.systemUptime-start)/0.36)
            self.opacity=1-pow(1-progress,3)
            if progress>=1 { timer.invalidate();self.timer=nil }
        }
    }
    func finish() { timer?.invalidate();timer=nil;opacity=1 }
    deinit { timer?.invalidate() }
}
private struct VineArrival:ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.vineStaticPreview) private var preview
    @Environment(\.vineReducedPreview) private var reducedPreview
    @StateObject private var clock=VineFadeClock()
    func body(content:Content)->some View {
        content.opacity(preview || reduced || reducedPreview ? 1:clock.opacity)
            .onAppear { clock.start(immediate:preview || reduced || reducedPreview) }
            .onDisappear { clock.finish() }
    }
}
