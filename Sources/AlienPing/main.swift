import AppKit
import SwiftUI
import ApplicationServices
import AlienCore

final class Delegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var status: NSStatusItem!
    var window: NSWindow?
    var mascotStage: MascotStageController?
    var terminationSignal: DispatchSourceSignal?
    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Psst")
        let menu=NSMenu()
        let stageItem=NSMenuItem(title:"Mascot Stage",action:#selector(showMascotStage),keyEquivalent:"m");stageItem.target=self
        menu.addItem(stageItem)
        let settingsItem=NSMenuItem(title:"Psst Settings",action:#selector(showSettings),keyEquivalent:",");settingsItem.target=self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title:"Quit Psst",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"))
        status.menu=menu
        status.button?.target = self; status.button?.action = #selector(showSettings)
        signal(SIGTERM, SIG_IGN)
        terminationSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminationSignal?.setEventHandler { NSApp.terminate(nil) }
        terminationSignal?.resume()
        DistributedNotificationCenter.default().addObserver(self,selector:#selector(showMascotStage),name:NSNotification.Name("local.alienping.showMascotStage"),object:nil)
        _ = SpriteLibrary.shared
        model.monitor.start()
        if CommandLine.arguments.contains("-mascotPreview") { showMascotStage() }
        else if !CommandLine.arguments.contains("--login-item") { showSettings() }
        if CommandLine.arguments.contains("--preview-all") {
            DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                self.model.preview(.claude)
                self.model.preview(.codex)
            }
        }
        if CommandLine.arguments.contains("--preview") {
            DispatchQueue.main.asyncAfter(deadline: .now()+1) { self.model.preview() }
        }
    }
    @objc func showMascotStage() {
        if mascotStage == nil { mascotStage=MascotStageController() }
        mascotStage?.present()
        NSApp.activate(ignoringOtherApps:true)
    }
    @objc func showSettings() {
        model.refreshApplications()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 720), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Psst"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.monitor.stop() }
}
let app = NSApplication.shared
if CommandLine.arguments.contains("--diagnostics") {
    // Report the running app's state, not this CLI process's TCC attribution.
    let state = Diagnostics.shared.stateURL
    if let data = try? Data(contentsOf: state), let text = String(data: data, encoding: .utf8) { print(text) }
    else { print("No runtime status yet. Open Psst.app first.") }
    print("Diagnostic log: \(Diagnostics.shared.logURL.path)")
    exit(0)
}
if let index=CommandLine.arguments.firstIndex(of:"--render-mascots") {
    let defaultPath=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/MascotPreview").path
    let path=CommandLine.arguments.count > index+1 ? CommandLine.arguments[index+1] : defaultPath
    do { try MascotMovie.renderAll(to:URL(fileURLWithPath:path));exit(0) }
    catch { fputs("Mascot export failed: \(error.localizedDescription)\n",stderr);exit(1) }
}
if CommandLine.arguments.contains("--show-mascot-stage") {
    DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("local.alienping.showMascotStage"),object:nil,userInfo:nil,deliverImmediately:true)
    exit(0)
}
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
