import AppKit
import SwiftUI
import AlienCore

struct CompanionPortrait: NSViewRepresentable {
    let source: SourceApp
    func makeNSView(context:Context) -> NSImageView {
        let view=NSImageView();view.imageScaling = .scaleProportionallyUpOrDown;return view
    }
    func updateNSView(_ view:NSImageView,context:Context) {
        let id=source == .claude ? "sunburst" : "terminal"
        if let frame=SpriteLibrary.shared.animation(id,"idle","east")?.frames.first {
            view.image=NSImage(cgImage:frame,size:NSSize(width:frame.width,height:frame.height))
        }
        view.setAccessibilityLabel("Claude sunburst and Codex terminal companions")
    }
}
