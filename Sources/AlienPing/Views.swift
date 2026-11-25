import SwiftUI
import AlienCore

/// The tail points to the companion docked outside the text surface.
struct NotificationBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let left:CGFloat=12, r:CGFloat=22, w=rect.width, h=rect.height
        var p=Path()
        p.move(to:CGPoint(x:left+r,y:0))
        p.addLine(to:CGPoint(x:w-r,y:0))
        p.addQuadCurve(to:CGPoint(x:w,y:r),control:CGPoint(x:w,y:0))
        p.addLine(to:CGPoint(x:w,y:h-r))
        p.addQuadCurve(to:CGPoint(x:w-r,y:h),control:CGPoint(x:w,y:h))
        p.addLine(to:CGPoint(x:left+7,y:h))
        p.addQuadCurve(to:CGPoint(x:left,y:h-7),control:CGPoint(x:left,y:h))
        p.addLine(to:CGPoint(x:left,y:h-20))
        p.addQuadCurve(to:CGPoint(x:0,y:h-30),control:CGPoint(x:3,y:h-22))
        p.addQuadCurve(to:CGPoint(x:left,y:h-43),control:CGPoint(x:10,y:h-31))
        p.addLine(to:CGPoint(x:left,y:r))
        p.addQuadCurve(to:CGPoint(x:left+r,y:0),control:CGPoint(x:left,y:0))
        p.closeSubpath();return p
    }
}

struct PingView: View {
    let ping: Ping
    let color: Color
    let hideText: Bool
    let open: () -> Void
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false
    private var appearance:NotificationAppearance { NotificationAppearance(source:ping.source,scheme:scheme) }
    private var ink:Color { appearance.ink }
    private var secondary:Color { appearance.secondary }
    private var paper:Color { appearance.paper }
    private var edge:Color { appearance.edge }
    private var accent:Color { appearance.accent }
    var body: some View {
        ZStack(alignment:.topTrailing) {
            Button(action:open) {
                VStack(alignment:.leading,spacing:5) {
                    HStack(spacing:8) {
                        Text(ping.source.rawValue).font(.system(size:11,weight:.semibold)).foregroundStyle(accent)
                        Spacer()
                        Text(ping.preview ? "Preview" : "now").font(.system(size:11)).foregroundStyle(secondary)
                    }.padding(.trailing,25)
                    Text(hideText ? "New notification" : ping.title)
                        .font(NotificationAppearance.title).tracking(-0.2).lineLimit(1)
                        .frame(maxWidth:.infinity,alignment:.leading)
                    Text(hideText ? "Your message is ready to read." : ping.body)
                        .font(.system(size:13)).foregroundStyle(secondary).lineLimit(2)
                        .frame(maxWidth:.infinity,alignment:.leading)
                    Spacer(minLength:3)
                    HStack(spacing:6) {
                        Spacer()
                        Text(ping.actionLabel ?? (ping.openNotification == nil ? "Open \(ping.source.rawValue)" : "Open chat"))
                        Image(systemName:"arrow.up.right").font(.system(size:10,weight:.medium))
                    }.font(.system(size:12,weight:.medium)).foregroundStyle(accent)
                }
                .padding(.leading,29).padding(.trailing,18).padding(.vertical,14)
                .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading)
                .contentShape(NotificationBubble())
            }.buttonStyle(.plain).foregroundStyle(ink)
                .accessibilityLabel("Open \(ping.source.rawValue): \(hideText ? "New notification" : ping.title)")
            Button(action:dismiss) {
                Image(systemName:"xmark").font(.system(size:10,weight:.medium))
                    .frame(width:30,height:30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(secondary)
                .accessibilityLabel("Dismiss notification").help("Dismiss notification").padding(5)
        }
        .background(NotificationBubble().fill(paper))
        .overlay(NotificationBubble().stroke(edge.opacity(hovered ? 1 : 0.8),lineWidth:1).allowsHitTesting(false))
        .shadow(color:appearance.shadow,radius:4,x:0,y:2)
        .padding(.leading,60).padding(.trailing,6).padding(.vertical,6)
        .onHover { hovered=$0 }
    }
}

struct SettingsView: View {
    @ObservedObject var model: Model
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 9) {
                    Image(systemName: "sparkle").foregroundStyle(Color(hex: "77D69D"))
                    Text("Psst").font(.system(size: 21, weight: .semibold))
                }
                Spacer(minLength: 0)
                CompanionPortrait(source:model.selected).frame(width:190,height:190).frame(maxWidth:.infinity)
                Text("A little more\notherworldly.").font(.system(size: 27, weight: .semibold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Text("Your apps. Their own colours.\nA visitor with every message.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75)).lineSpacing(4)
                Spacer(minLength: 0)
                Label(model.trusted ? (model.enabled ? "Listening for visitors" : "Taking a break") : "Preview mode", systemImage: model.trusted && model.enabled ? "dot.radiowaves.left.and.right" : "moon")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: "A4DDBD"))
            }.padding(28).frame(width: 240).frame(maxHeight: .infinity)
                .background(Color(red: 0.10, green: 0.18, blue: 0.20)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Meet your messenger").font(.system(size: 23, weight: .semibold))
                        Text("Make every arrival feel different.").foregroundStyle(.secondary)
                        Button("Tray, quiet mode & personalization") { model.attention.showInbox?() }.buttonStyle(.link)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: $model.enabled).toggleStyle(.switch).labelsHidden().help("Enable live notifications")
                }
                if !model.trusted {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "hand.raised").font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connect your notifications").fontWeight(.semibold)
                            Text("Allow Psst in Accessibility. Your messages stay on this Mac.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("Connect", action: model.connect)
                    }.padding(14).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Claude & Codex").font(.headline)
                    if model.availableApps.isEmpty { Text("No supported apps found. Install Claude or Codex, then reopen this window.").foregroundStyle(.secondary) }
                    ForEach(model.availableApps) { app in
                        HStack(spacing: 12) {
                            Toggle(app.rawValue, isOn: Binding(get: { !model.disabled.contains(app.rawValue) }, set: { on in
                                model.disabled.removeAll { $0 == app.rawValue }; if !on { model.disabled.append(app.rawValue) }
                            })).toggleStyle(.checkbox).frame(width: 118, alignment: .leading)
                            ColorPicker("\(app.rawValue) colour", selection: Binding(get: { model.color(app) }, set: { model.colors[app.rawValue] = $0.hex }), supportsOpacity: false).labelsHidden()
                            Spacer()
                            Button("Preview") { model.selected = app; model.preview(app) }.buttonStyle(.bordered).controlSize(.small)
                        }.padding(.vertical, 3)
                        if app != model.availableApps.last { Divider() }
                    }
                }
                Divider()
                HStack {
                    Text("Message corner").frame(width: 110, alignment: .leading)
                    Picker("Message corner", selection: $model.corner) { ForEach(Corner.allCases.filter { $0 != .random }) { Text($0.rawValue).tag($0) } }.labelsHidden()
                }
                Text("Characters arrive from random points along the screen edges.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Stay for").frame(width: 110, alignment: .leading)
                    Slider(value: $model.duration, in: 3...15, step: 1)
                    Text("\(Int(model.duration)) sec").monospacedDigit().frame(width: 48)
                }
                Text("Pauses while you hover over a notification.").font(.caption).foregroundStyle(.secondary)
                Toggle("Hide message text", isOn: $model.hideText)
                VStack(alignment: .leading, spacing: 5) {
                    Toggle("Move the original banner out of view", isOn: $model.replace)
                    Text("Experimental. If macOS refuses, the original stays visible. Keep app banners enabled in System Settings.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(minHeight: 30, alignment: .topLeading)
                HStack {
                    Button("Quit Psst") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Spacer()
                    Button("Send a visitor") { model.preview() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: []).disabled(model.availableApps.isEmpty)
                }
            }.padding(28).frame(width: 500).frame(maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
        }.frame(width: 740, height: 720)
    }
}
