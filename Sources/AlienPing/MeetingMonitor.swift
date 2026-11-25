import AppKit
import ApplicationServices
import AlienCore

/// Heuristic: context plus active-call controls, never page title alone.
/// Reads only labels/roles needed for detection; no screenshots, audio or stored URLs.
final class MeetingMonitor {
    private(set) var active=false
    private(set) var status="Automatic call detection is starting."
    private var timer:Timer?
    private let worker=DispatchQueue(label:"Psst.meeting-detection",qos:.utility)
    private var busy=false
    private var lastPositive=Date.distantPast
    private var stopped=false
    private let browsers:Set<String>=["com.google.Chrome","com.apple.Safari","com.microsoft.edgemac","com.brave.Browser","company.thebrowser.Browser","org.mozilla.firefox"]
    func start() { timer?.invalidate();stopped=false;timer=Timer.scheduledTimer(withTimeInterval:5,repeats:true){[weak self] _ in self?.scan()};scan() }
    func stop() { active=false;lastPositive = .distantPast;stopped=true;timer?.invalidate();timer=nil }
    private func scan() {
        guard !busy,!stopped else { return }
        guard AXIsProcessTrusted() else { active=false;status="Allow Accessibility for meeting detection.";return }
        let apps=NSWorkspace.shared.runningApplications.filter{browsers.contains($0.bundleIdentifier ?? "") || $0.bundleIdentifier=="us.zoom.xos"}
        busy=true
        worker.async { [weak self] in
            guard let self else { return }
            let deadline=Date().addingTimeInterval(1.5)
            var found=false,visited=0
            func read(_ node:AXUIElement,_ key:String)->CFTypeRef? { var value:CFTypeRef?;guard Date()<deadline,AXUIElementCopyAttributeValue(node,key as CFString,&value) == .success else { return nil };return value }
            func examine(_ node:AXUIElement,context:String,depth:Int)->Bool {
                guard depth<22,visited<3500,Date()<deadline else { return false };visited+=1
                let role=read(node,kAXRoleAttribute) as? String ?? ""
                var context=context
                if role == "AXWebArea",let url=read(node,"AXURL") as? URL, url.host=="meet.google.com" { context="Google Meet" }
                if role == kAXButtonRole || role == "AXMenuButton" {
                    let labels=[read(node,kAXTitleAttribute) as? String ?? "",read(node,kAXDescriptionAttribute) as? String ?? ""]
                    if MeetingEvidence.active(context:context,buttons:labels) { return true }
                }
                let children=read(node,kAXChildrenAttribute) as? [AXUIElement] ?? []
                for child in children { if examine(child,context:context,depth:depth+1) { return true } }
                return false
            }
            for app in apps {
                let root=AXUIElementCreateApplication(app.processIdentifier);AXUIElementSetMessagingTimeout(root,0.03)
                let windows=read(root,kAXWindowsAttribute) as? [AXUIElement] ?? []
                for window in windows {
                    let title=read(window,kAXTitleAttribute) as? String ?? ""
                    let context=(app.bundleIdentifier=="us.zoom.xos" ? "Zoom " : "")+title
                    if examine(window,context:context,depth:0) { found=true;break }
                }
                if found { break }
            }
            DispatchQueue.main.async {
                self.busy=false;guard !self.stopped else { return }
                if found { self.lastPositive=Date() }
                self.active=found || Date().timeIntervalSince(self.lastPositive)<60
                self.status=found ? "Active Meet or Zoom call controls detected." : (self.active ? "Keeping quiet briefly while call controls are hidden." : "No active call detected. Hidden tabs and non-English controls may need manual Quiet mode.")
            }
        }
    }
}
