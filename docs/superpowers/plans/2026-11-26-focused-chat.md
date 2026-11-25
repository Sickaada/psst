# Foreground chat suppression

Requested: do not repeat a notification for the chat the user is already viewing.

Implemented exact, non-generic title matching scoped to native Claude/Codex. A bounded Accessibility read inspects only the focused window and selected tab labels. It does not inspect arbitrary sidebar/chat text. Idle over60s is not treated as reading. Pending requests cannot reuse earlier samples. Window/title/tab evidence is revalidated before marking anything read; uncertain evidence preserves the alert. Shutdown drains pending notification inspections conservatively.

Incoming matched notifications are stored read and do not enter the vine or delivery queue. Periodic focused-chat matching removes existing unread leaves and associated alerts. Summary overlays track remaining IDs cumulatively. Focus titles are never logged or persisted.

Validation: core tests cover same-chat, wrong-app, different-chat, generic titles and arbitrary-body mentions. Native build and offscreen vine harness passed. Static review found and confirmed fixes for stale evidence, shutdown loss and cumulative summary removal. A real incoming notification and app-specific Accessibility labels still require live validation; this is best-effort matching, not a guaranteed chat-ID integration.
