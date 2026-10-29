# Clipt — design

Date: 2026-10-29 · Status: draft for approval

## Intent

Clipt is a clipboard history app for macOS: Maccy's job, done much more beautifully.

Brent used Raycast only for its clipboard history and found the rest of Raycast
unnecessary, so he went back to Spotlight. Spotlight's built-in clipboard history (macOS 26+)
is too slow to reach: there is no direct shortcut, only ⌘Space then ⌘4, and it doesn't paste
into the app you came from. His real use is "press a key, arrow down to one of the last few
items, Return, it's pasted". Clipt makes exactly that instant, and makes it look and feel like
part of macOS.

It's a personal tool, published free and open source (MIT) on GitHub like his other Mac apps
(Glint, Stash, Catchbox).

### What the research says (summary)

- **Gap in the market:** nobody combines Maccy-level speed with a real Liquid Glass,
  Apple-native look and no subscription. The polished apps (Paste, Raycast Pro, Pastebot on
  the App Store) are subscriptions. The fast ones (Maccy, Clipy, ClipBook) look utilitarian.
- **Most-requested:** one instant hotkey; ⌘1–9 to paste the last items directly; a small
  list with the deep history searchable; paste-on-select into the previous app; pins;
  plain-text paste as an option, not forced.
- **Top complaints about existing apps:** lag and memory that grows linearly (Maccy),
  paste not working (Accessibility), breakage on each macOS release, bloat or intrusive UI
  (Paste), subscriptions.
- **Privacy expectations:** ignore password managers by default, ignore per app, local
  storage only, auto-expiry.

## Goals

1. **One hotkey, instant.** ⌘⇧C (user-remappable) shows the panel with the newest item
   already selected. ↓↓ ↩ pastes into the frontmost app. The panel is on screen within one
   frame of the keypress — no perceptible delay, also with thousands of items.
2. **Looks native.** A Spotlight-style Liquid Glass panel, centered horizontally in the
   upper part of the screen, on the display that has the mouse/active window. It should read
   as something Apple shipped.
3. **Beautiful motion.** Spring-based animations throughout (see Motion). Respects Reduce
   Motion.
4. **Optimized.** Flat memory use regardless of history size, instant search, negligible CPU
   while idle.
5. **Private by default.** Local only, password managers ignored, user-defined ignore list.

## Non-goals (v1)

- No launcher, no snippets engine, no AI features, no pinboards/collections beyond pins.
- No iCloud/cross-device sync, no iOS app.
- No Mac App Store build (auto-paste and sandbox review risk; see Distribution).
- No localization: **all UI text is English**.

## Anti-goals (failure even if it works)

- Any visible lag opening the panel or moving the selection.
- Memory that keeps growing with history size.
- Pasting into the wrong app, or a paste that silently does nothing.
- A cluttered, "power-user dashboard" look. If a feature makes the panel busier for the
  common case (last few items), it doesn't belong on the main surface.
- Storing a password from a password manager.

## The panel (decided)

Spotlight-style, as in the approved mockup (option B): `mockups/panel.html` next to this
document (open it in a browser). `mockups/panel-shape-options.html` shows the three shapes
that were compared; A (at cursor) and C (bottom shelf) were rejected.

Proportions from the mockup: panel ~640 pt wide; list takes ~half the width, preview the
rest; the preview pane is always shown; filter chips sit at the right end of the search
row; ~8–9 rows visible without scrolling (pinned section included).

- **Search field** on top ("Search clipboard…"), focused on open. Typing filters the whole
  history; the list shows the newest items when the field is empty.
- **Type filter chips** next to the search field: All · Text · Images · Links.
- **Left: the list.** A "Pinned" section on top (when there are pins), then "Recent". Each
  row: icon of the source app, a one-line preview, and on the right the ⌘1–⌘9 hint for the
  first nine recent items. The newest item is selected on open.
- **Right: a preview** of the selected item (full text in a rounded box, image thumbnail,
  link), with metadata: source app, when it was copied, type and size.
- **Footer hint bar:** ↩ Paste · ⌥↩ Paste as plain text · ⌘P Pin · ⌫ Delete · esc Close.

### Keyboard

| Key | Action |
|---|---|
| ⌘⇧C | Toggle the panel (global). Remappable in Settings. |
| ↑ / ↓ | Move selection |
| ↩ | Paste selected item into the previous app, close panel |
| ⌥↩ | Paste as plain text |
| ⌘1–⌘9 | Paste that recent item directly |
| ⌘P | Pin / unpin |
| ⌫ (search field empty) | Delete selected item |
| esc | Clear search, or close if search is empty |
| Typing | Search |

**⌘1–⌘9 follow what's on screen (Claude's call):** the hints sit on the first nine visible
rows of the current list (after search and filter, pinned rows excluded), and ⌘N pastes
exactly the row showing ⌘N. The hint and the action can never disagree.

Clicking a row pastes it. Clicking outside the panel or switching apps closes it.

**Known conflict (Brent's call to keep ⌘⇧C):** ⌘⇧C is the element inspector in Chrome and
Safari and "Computer" in the Finder; a global hotkey takes it over everywhere. Settings
makes it easy to change.

## Behaviour

- **Capture:** text (plain + rich: RTF/HTML kept, so ↩ pastes with formatting and ⌥↩ without),
  images, file references (Finder copies), links (text recognized as URL), colors (hex
  strings get a swatch). Each item records the source app (frontmost app at copy time) and
  timestamp. Copying something that's already in history moves it to the top instead of
  duplicating it.
- **Fidelity (Claude's call):** store every representation the source app put on the
  pasteboard (so an Excel range or Keynote shape pastes back as it was), up to a per-item cap
  (~20 MB total; above that keep only the types Clipt understands). Duplicate detection uses
  a hash of the item's primary representation (plain text, else image data, else file URLs).
- **Image text search (Claude's call):** images are OCR'd on-device with Vision in the
  background after capture (like Glint's `TextRecognizer`), and the text goes into the
  search index.
- **Paste:** Clipt puts the item on the pasteboard, closes the panel, reactivates the
  previous app and synthesizes ⌘V. The item stays on the pasteboard afterwards (it becomes
  the newest item), which is what users expect.
- **Pins** stay forever and never count toward the history limit.
- **Retention:** default keep the last 1,000 unpinned items, configurable (e.g. 200 / 1,000 /
  5,000 / unlimited) plus optional age limit (1 day / 7 days / 30 days / forever, default
  forever). "Clear history" in the menu and Settings.
- **Privacy:**
  - Skip items carrying `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`,
    `org.nspasteboard.AutoGeneratedType`, `com.agilebits.onepassword`,
    `de.petermaurer.TransientPasteboardType` — check types *before* reading content.
  - Per-app ignore list in Settings, pre-filled with Passwords, Keychain Access, 1Password,
    Bitwarden.
  - "Pause capture" toggle in the menu bar menu.
  - Panel windows are excluded from screen capture/sharing (`sharingType = .none`).
  - Everything stays on disk in Application Support; no network except the update check.
- **Menu bar item:** small icon with a menu: Open Clipt (⌘⇧C), Pause capture, Clear history,
  Settings…, Check for updates…, Quit. Option to hide the icon. Launch at login toggle
  (on by default after onboarding).

## Motion

One motion system for the whole app, modeled on Glint's `Motion.swift` (real springs,
Reduce Motion → plain fades):

- **Open:** panel springs in, a slight scale up from ~0.96 plus fade, tiny bounce. Close is
  quicker and has no bounce.
- **Selection:** the highlight glides between rows (matched geometry), never jumps. Holding
  ↓ stays smooth.
- **List changes:** filtering/search reflows rows with a spring; deleted rows collapse away;
  a newly pinned row slides into the Pinned section.
- **Preview:** cross-fades when the selection changes.
- **Paste:** a brief confirmation (the row pulses, then the panel springs out).

## Onboarding & permissions

First launch shows a short native-looking welcome window that walks through:

1. **Accessibility** (needed to synthesize ⌘V). Explain why, button opens the request; show a
   live check mark once granted. Without it, Clipt still works but only copies the item and
   says "Press ⌘V to paste".
2. **Pasteboard access** ("Paste from Other Apps" in Privacy & Security, introduced in macOS
   15.4 and likely on by default from 27.2). Read `NSPasteboard.accessBehavior`; if it's not
   `.alwaysAllow`, explain in words how to set it to "Allow" (Apple asks apps not to
   deep-link there). Use the pasteboard `detect…` APIs where possible so checking types
   doesn't trigger the alert. Show a recoverable warning in the panel if access is later
   denied.
   **While access isn't "Allow" (Claude's call):** capture is paused — Clipt never reads
   pasteboard content in "Ask" mode, so the system alert can't fire on every copy. The state
   is never silent: the menu bar icon shows a paused badge and the panel shows a banner
   ("Clipt can't see new copies — allow it in Privacy & Security → Paste from Other Apps")
   above the existing history. Onboarding can be skipped; this banner then carries it.
3. Hotkey (shows ⌘⇧C, change here) and Launch at login.

## Technical approach (Claude's calls, following Brent's existing apps)

- **Platform:** macOS 26 or later (Liquid Glass APIs), developed and tested on macOS 27.
  Swift 6, SwiftUI inside AppKit windows.
- **Project layout like Glint/Catchbox:** Swift Package with `CliptCore` (library: models,
  storage, search, capture filtering, retention — no AppKit UI), `Clipt` (executable app),
  `CliptTests` (plain executable test runner, since XCTest needs full Xcode). `Makefile` with
  `build / bundle / install / run / test / zip / icon`, universal binary (arm64 + x86_64).
- **No third-party dependencies** (like Glint). Reuse/adapt Glint's `HotKeys` (Carbon
  `RegisterEventHotKey`, no permission needed), `ShortcutRecorder`, `Motion`, `Updater`
  (GitHub Releases) and the self-signed signing certificate script — the stable identity is
  essential here because the Accessibility grant is lost whenever the signature changes.
- **Monitoring:** poll `NSPasteboard.general.changeCount` (~0.25 s timer, coalesced, near-zero
  CPU). On change: check types/ignore rules first, then read.
- **Panel:** non-activating `NSPanel` subclass that can become key (so the previous app stays
  frontmost and receives ⌘V), floating level, joins all Spaces and full-screen apps. SwiftUI
  content in a `GlassEffectContainer` with `.glassEffect`. The panel is created once and kept
  around hidden, so opening is just showing it.
- **Storage:** SQLite via the system `libsqlite3` (no package), WAL mode, with an FTS5 index
  for search. Images and large payloads stored as files keyed by content hash, with a small
  thumbnail; the database keeps metadata and paths. The list loads in pages; only visible
  rows and their thumbnails are in memory.
- **Paste:** `CGEvent` ⌘V posted to the session event tap after the previous app is
  reactivated.
- **Signing (Brent's decision):** one self-signed "Clipt" code-signing certificate, created
  once, stored as a GitHub Actions secret (p12 + password) and in Brent's keychain. The
  release workflow and local `make bundle` both sign with it, so every install keeps a stable
  identity and the Accessibility grant survives updates for everyone, not just on Brent's
  Mac. The Updater verifies a downloaded update carries the same signing identity before
  installing. Not notarized: first install still needs the quarantine step, documented in the
  README like Catchbox. As a safety net, Clipt detects a lost Accessibility grant at paste
  time and shows the re-enable prompt instead of failing silently.
- **Distribution:** GitHub Releases zip + cask `brentc22/tap/clipt`, like Glint. README in
  English with screenshots.

## Left to the builder

- Exact dimensions, corner radii, typography sizes, colors — within "looks like Spotlight on
  macOS 26/27" and the approved mockup.
- Spring parameters and timings.
- Icon design (glass-style clipboard glyph; generated by a script like Glint's `make-icon`).
- Internal module structure, schema details, migration approach.
- Performance budgets for tests (target: panel visible < 16 ms after hotkey on warm start;
  search over 10k items < 50 ms; memory roughly flat from 100 to 10k items).
