import SwiftUI
import AlienCore

/// Shared by live speech bubbles and saved vine messages.
struct NotificationAppearance {
    let source:SourceApp
    let scheme:ColorScheme
    private var codex:Bool { source == .codex }
    private var dark:Bool { scheme == .dark }
    var ink:Color { Color(hex:dark ? (codex ? "E5F3FF":"FFF0DE") : (codex ? "21384D":"423124")) }
    var secondary:Color { Color(hex:dark ? (codex ? "A9C5DA":"C6B6A5") : (codex ? "516B82":"806D5B")) }
    var paper:Color { Color(hex:dark ? (codex ? "25292C":"2C2825") : (codex ? "F7FAFC":"FCF9F5")) }
    var edge:Color { Color(hex:dark ? "494B4B" : "DDDCD8") }
    var accent:Color { Color(hex:dark ? (codex ? "81C9ED":"EDA47F") : (codex ? "347798":"A8603F")) }
    var shadow:Color { .black.opacity(dark ? 0.18:0.08) }
    static let title=Font.system(size:21,weight:.semibold)
    static let body=Font.system(size:18)
    static let label=Font.system(size:15,weight:.semibold)
}
