# Psst design

Native AppKit overlay panels with SwiftUI speech bubbles. Warm cream/orange for Claude; pale/deep blue for Codex, adapting to system appearance. Text has a clear source, title, two-line body and Open chat action; dismiss is a separate control. A bubble tail points to the mascot outside the text area. Card footprint: 420×166 points, up to three cards stacked at 178-point intervals.

Original procedural 3D character poses are pre-rendered into RGBA sprite atlases. Each entrance has 64 frames over 2.65 seconds; idle cycles use 24 frames. Cached native layers play the frames without runtime generation, WebGL or network access. The eight-style shuffle and path selection are separate; each notification gets an independently sampled screen-edge origin. Hover pauses expiry; Reduce Motion freezes pose and skips travel.
