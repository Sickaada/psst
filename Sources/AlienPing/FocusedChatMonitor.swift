import AppKit
import ApplicationServices
import AlienCore

/// Reads only the foreground app's focused window title and selected tab labels.
/// No screenshots, chat history, unselected sidebar items or persisted focus data.
final class FocusedChatMonitor {
    private let worker=DispatchQueue(label:"Psst.focused-chat",qos:.utility)
    private var timer:Timer?
    private var busy=false
    private var pending:((FocusedChat?)->Void)?
    private var generation=0
    func start(onFocus:@escaping(FocusedChat)->Void) {
        timer?.invalidate()
        Diagnostics.shared.event("focused_chat_monitor_started",["sourceApps":2])
        timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
            guard let self,!self.busy else { return }
            self.inspect { if let context=$0 { onFocus(context) } }
        }
    }
    func stop() {
        generation+=1;timer?.invalidate();timer=nil;busy=false
        let callback=pending;pending=nil
        callback?(nil) // Preserve an incoming notification when shutting down mid-inspection.
    }
    func inspect(_ completion:@escaping(FocusedChat?)->Void) {
        // A visible window is not evidence that an idle/away person has read it.
        let idle=CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType:CGEventType(rawValue:UInt32.max)!)
        guard idle<60,AXIsProcessTrusted(),let app=NSWorkspace.shared.frontmostApplication,
              let source=Self.source(app.bundleIdentifier) else { completion(nil);return }
        // Never reuse a sample that began before this notification arrived.
        guard !busy else { completion(nil);return }
        pending=completion;busy=true
        let pid=app.processIdentifier,run=generation
        worker.async { [weak self] in
            let root=AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root,0.035)
            let deadline=Date().addingTimeInterval(0.2)
            func read(_ element:AXUIElement,_ key:String)->CFTypeRef? {
                guard Date()<deadline else { return nil }
                AXUIElementSetMessagingTimeout(element,0.035)
                var value:CFTypeRef?
                return AXUIElementCopyAttributeValue(element,key as CFString,&value) == .success ? value:nil
            }
            var titles:[String]=[]
            var sampledWindow:AXUIElement?
            var sampledTitle:String?
            var selectedTabs:[(AXUIElement,String)]=[]
            if let value=read(root,kAXFocusedWindowAttribute),CFGetTypeID(value)==AXUIElementGetTypeID() {
                let window=unsafeBitCast(value,to:AXUIElement.self)
                sampledWindow=window
                sampledTitle=read(window,kAXTitleAttribute) as? String
                if let title=sampledTitle,!title.isEmpty { titles.append(title) }
                var visited=0
                func visit(_ node:AXUIElement,_ depth:Int) {
                    guard depth<12,visited<250,Date()<deadline else { return };visited+=1
                    let role=read(node,kAXRoleAttribute) as? String ?? ""
                    var isTab=["AXTab","AXTabButton"].contains(role)
                    if role=="AXRadioButton",let parent=read(node,kAXParentAttribute),CFGetTypeID(parent)==AXUIElementGetTypeID() {
                        isTab=(read(unsafeBitCast(parent,to:AXUIElement.self),kAXRoleAttribute) as? String)=="AXTabGroup"
                    }
                    if isTab,selectedTabs.count<4,
                       (read(node,kAXSelectedAttribute) as? Bool == true || read(node,kAXValueAttribute) as? Int == 1),
                       let title=read(node,kAXTitleAttribute) as? String,!title.isEmpty { titles.append(title);selectedTabs.append((node,title)) }
                    for child in read(node,kAXChildrenAttribute) as? [AXUIElement] ?? [] { visit(child,depth+1) }
                }
                visit(window,0)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.generation==run else { return }
                self.busy=false
                let validationDeadline=Date().addingTimeInterval(0.06)
                AXUIElementSetMessagingTimeout(root,0.015)
                func current(_ node:AXUIElement,_ key:String)->CFTypeRef? {
                    guard Date()<validationDeadline else { return nil }
                    AXUIElementSetMessagingTimeout(node,0.015)
                    var value:CFTypeRef?
                    return AXUIElementCopyAttributeValue(node,key as CFString,&value) == .success ? value:nil
                }
                var stillFocused=NSWorkspace.shared.frontmostApplication?.processIdentifier==pid
                if stillFocused,let sampledWindow,let focused=current(root,kAXFocusedWindowAttribute) {
                    stillFocused=CFEqual(focused,sampledWindow) && (current(sampledWindow,kAXTitleAttribute) as? String)==sampledTitle
                    for (tab,label) in selectedTabs where stillFocused {
                        stillFocused=(current(tab,kAXSelectedAttribute) as? Bool == true || current(tab,kAXValueAttribute) as? Int == 1) && (current(tab,kAXTitleAttribute) as? String)==label
                    }
                } else { stillFocused=false }
                let context=stillFocused && !titles.isEmpty ? FocusedChat(source:source,titles:titles):nil
                let callback=self.pending;self.pending=nil
                callback?(context)
            }
        }
    }
    private static func source(_ bundle:String?)->SourceApp? {
        switch bundle { case "com.anthropic.claudefordesktop":return .claude;case "com.openai.codex":return .codex;default:return nil }
    }
}
