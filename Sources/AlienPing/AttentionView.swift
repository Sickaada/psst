import SwiftUI
import AlienCore

struct AttentionView:View {
    @ObservedObject var attention:AttentionController
    @ObservedObject var model:Model
    @State var tab=0
    @State private var unreadOnly=true
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text("Ready when you are.").font(.system(size:26,weight:.semibold,design:.rounded))
                    Text(attention.isQuiet ? "\(attention.quietReason) · notifications are saved quietly" : "\(attention.inbox.unreadCount) unread · everything stays on this Mac")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName:attention.isQuiet ? "moon.fill":"tray.fill").font(.title).foregroundStyle(.blue)
            }
            Picker("View",selection:$tab) { Text("Your tray").tag(0);Text("Quiet & personal").tag(1) }.pickerStyle(.segmented)
            if tab == 0 { tray } else { preferences }
            if !attention.storageError.isEmpty { Text(attention.storageError).font(.caption).foregroundStyle(.red) }
        }.padding(24).frame(minWidth:510,minHeight:500).background(Color(nsColor:.windowBackgroundColor))
    }
    private var tray:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Toggle("Unread only",isOn:$unreadOnly).toggleStyle(.checkbox)
                Spacer()
                Button("Mark all read",action:attention.markAllRead).disabled(attention.inbox.unreadCount==0)
                Button("Clear read") { for entry in attention.inbox.entries where entry.read { attention.remove(entry.id) } }
            }
            ScrollView {
                if attention.inbox.entries.filter({!unreadOnly || !$0.read}).isEmpty {
                    VStack(spacing:12) {
                        Image(systemName:"checkmark.circle").font(.system(size:36)).foregroundStyle(.secondary)
                        Text("You’re all caught up.").font(.headline)
                        Text("New notifications will wait here—even if you miss their entrance.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth:.infinity).padding(.vertical,65)
                }
                ForEach([SourceApp.claude,.codex]) { source in
                    let entries=attention.inbox.entries.filter{$0.source==source && (!unreadOnly || !$0.read)}
                    if !entries.isEmpty {
                        VStack(alignment:.leading,spacing:10) {
                            HStack { Text(source.rawValue).font(.headline);Text("\(entries.count)").foregroundStyle(.secondary);Spacer() }.padding(.top,8)
                            ForEach(entries) { entry in
                                VStack(alignment:.leading,spacing:8) {
                                    HStack(alignment:.firstTextBaseline) {
                                        Text(model.hideText || entry.title.isEmpty ? "Notification from \(source.rawValue)" : entry.title).font(.system(size:14,weight:entry.read ? .regular:.semibold)).lineLimit(2)
                                        Spacer()
                                        Text(entry.date,style:.relative).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if !model.hideText && !entry.body.isEmpty { Text(entry.body).font(.system(size:13)).foregroundStyle(.secondary).lineLimit(3) }
                                    HStack {
                                        Button("Open \(source.rawValue)") { attention.open(entry) }
                                        if !entry.read { Button("Mark read") { attention.markRead(entry.id) } }
                                        Spacer()
                                        Button { attention.remove(entry.id) } label:{Image(systemName:"trash")}.accessibilityLabel("Remove saved notification")
                                    }.controlSize(.small)
                                }.padding(14).background(Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
                            }
                        }
                    }
                }
            }
            Text("Saved items open the app. The original notification’s chat action may have expired.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var preferences:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                GroupBox("Choose your moment") {
                    VStack(alignment:.leading,spacing:10) {
                        Picker("Delivery",selection:$attention.quietMode) { Text("Automatic").tag("Automatic");Text("Quiet").tag("Quiet");Text("Allow").tag("Allow") }.pickerStyle(.segmented)
                        Toggle("Quiet during detected Meet and Zoom calls",isOn:$attention.autoMeetings)
                        Text(attention.meetingStatus).font(.caption).foregroundStyle(.secondary)
                        Toggle("Save quietly after 2 minutes away",isOn:$attention.quietAway)
                        Text("Bursts within 2 seconds become one summary. After quiet time, you get one catch-up. Native banners may still appear if macOS refuses to hide them.").font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
                GroupBox("Privacy & keeping things") {
                    VStack(alignment:.leading,spacing:10) {
                        Toggle("Save message text on this Mac",isOn:$attention.storeContent)
                        Text("Off by default: only the app, time and read state survive a restart. Turning it off removes saved message text from disk. Up to 200 items, kept for 7 days.").font(.caption).foregroundStyle(.secondary)
                        Button("Clear all saved notifications",role:.destructive,action:attention.clear)
                    }.padding(8)
                }
                ForEach([SourceApp.claude,.codex]) { source in
                    GroupBox(source.rawValue) { CompanionChoices(attention:attention,model:model,source:source).padding(8) }
                }
            }.padding(.vertical,3)
        }
    }
}
struct CompanionChoices:View {
    @ObservedObject var attention:AttentionController
    @ObservedObject var model:Model
    let source:SourceApp
    private var settings:CompanionPreferences { attention.preference(source) }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Picker("Companion",selection:Binding(get:{settings.character},set:{ value in attention.change(source){$0.character=value} })) {
                    Text("Sunburst").tag("sunburst");Text("Terminal robot").tag("terminal")
                }
                ColorPicker("Accent",selection:Binding(get:{model.color(source)},set:{model.colors[source.rawValue]=$0.hex}),supportsOpacity:false)
            }
            HStack {
                Button("Playful preset") { attention.change(source){$0.styles=MascotStyle.allCases;$0.edges=ScreenEdge.allCases;$0.calm=false} }
                Button("Calm preset") { attention.change(source){$0.styles=[.floating,.peekaboo];$0.calm=true} }
                Spacer()
                Button("Preview") { model.preview(source) }
            }.controlSize(.small)
            Toggle("Calm delivery (stationary, subtle fade)",isOn:Binding(get:{settings.calm},set:{value in attention.change(source){$0.calm=value}}))
            Text("Shuffle these animations").font(.subheadline).fontWeight(.medium)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:8) {
                ForEach(MascotStyle.allCases,id:\.self) { style in
                    Toggle(style.rawValue.capitalized,isOn:Binding(get:{settings.styles.contains(style)},set:{on in attention.change(source){p in if on { p.styles.append(style) } else if p.styles.count>1 { p.styles.removeAll{$0==style} }}})).toggleStyle(.checkbox)
                }
            }
            Text("Enter from these edges").font(.subheadline).fontWeight(.medium)
            HStack {
                ForEach(ScreenEdge.allCases,id:\.self) { edge in
                    Toggle(edge.rawValue.capitalized,isOn:Binding(get:{settings.edges.contains(edge)},set:{on in attention.change(source){p in if on {p.edges.append(edge)} else if p.edges.count>1 {p.edges.removeAll{$0==edge}}}})).toggleStyle(.checkbox)
                }
            }
        }
    }
}
