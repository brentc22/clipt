# Changelog

## 0.1.0 — 2026-10-30

The first release: a clipboard history that opens on one keystroke and looks like part of
macOS 26.

- **One hotkey, instant.** <kbd>⌘⇧C</kbd> (remappable) opens a Liquid Glass panel with the
  newest item selected. <kbd>↓</kbd> <kbd>↩</kbd> pastes into the app you came from;
  <kbd>⌘1</kbd>–<kbd>⌘9</kbd> paste a visible row directly.
- **Captures** text (rich text stays rich), images, files, links and colors, with the app
  they came from. Copying something already in history moves it to the top.
- **Compact by design.** A 540 × 330 pt panel with dense rows; photos show as a small
  thumbnail with their pixel size, and the preview keeps them small.
- **Search** across the whole history, including text inside images (read on-device), with
  All / Text / Images / Links filters.
- **Pins** that never expire, plain-text paste (<kbd>⌥↩</kbd>), delete, and a preview pane.
- **Private by default.** Password managers and transient or concealed clipboard types are
  never saved; there is a per-app ignore list, a Pause Capture switch, and the panel is
  hidden from screen sharing. Everything stays in `~/Library/Application Support/Clipt`.
- **Retention**: keep 200, 1,000 (default), 5,000 or unlimited items, optionally dropping
  anything older than 1, 7 or 30 days.
- Spring motion throughout, plain fades with Reduce Motion.
- A menu bar item, launch at login, settings and a first-run walkthrough for the
  Accessibility and Paste from Other Apps permissions.
- **Self-updates.** Once a day Clipt asks GitHub whether there is a newer version and offers
  to install it (Install and Relaunch, Later, Skip This Version). The download is only
  installed if it is the same app, the promised version, and signed by the same identity as
  the copy you are running.
- Releases are signed with the `Clipt Self-Signed` identity (never ad-hoc), so the
  Accessibility permission survives updates.
