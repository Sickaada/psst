# Psst design

Native AppKit overlay panels with SwiftUI speech bubbles. Warm cream/orange for Claude; pale/deep blue for Codex, adapting to system appearance. Text has a clear source, title, two-line body and Open chat action; dismiss is a separate control. A bubble tail points to the mascot outside the text area. Card footprint: 420×166 points, up to three cards stacked at 178-point intervals.

Original procedural 3D character poses are pre-rendered into RGBA sprite atlases. Each entrance has 64 frames over 2.65 seconds; idle cycles use 24 frames. Cached native layers play the frames without runtime generation, WebGL or network access. The eight-style shuffle and path selection are separate; each notification gets an independently sampled screen-edge origin. Hover pauses expiry; Reduce Motion freezes pose and skips travel.


## Notification vine

A botanical transparent ornament follows the full available left-edge height. The six latest unread items with captured text appear as individual cream/blue cards; missing-text records remain only in the tray. Panel width 372pt, card radius14pt, system text14/12/11pt, quiet source accents. A 52×64pt control sits at the screen's vertical center for expand/collapse. Decorative regions pass clicks through. Each new row uses a stationary 360ms cubic ease-out opacity reveal; initial panel appearance fades 280ms. Reduce Motion shows content immediately. No perpetual animation or runtime image generation. The botanical asset is generated once and bundled locally.
