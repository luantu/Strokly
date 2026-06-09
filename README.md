# Strokly

Strokly is a macOS utility for **right-button mouse gestures**. Drag with the right mouse button anywhere on the OS — Strokly recognizes the gesture and executes configurable actions. 中文 & English.

| Gesture → | Keyboard shortcut | Open URL / app | Shell / AppleScript | System action |
|---|---|---|---|---|

## Features

- **Global capture** — low-level CGEvent tap intercepts right/middle/button4/button5 drags anywhere
- **Gesture trail overlay** — per-display real-time GPU-rendered path drawing at screen saver level (pure CAShapeLayer, no CPU draw overhead)
- **Hybrid recognition** — matches by direction tokens (U/D/L/R/UL/UR/DL/DR) **or** normalized template similarity (configurable 8%–42% tolerance)
- **Live preview** — shows matched rule name during drag, before mouse release
- **Direction confirmation** — requires 2 consecutive segments before accepting direction change, filters jitter
- **App-specific scoping** — per-bundle rules override global rules, enabling per-app gesture sets
- **Modifier key requirements** — require Ctrl/Opt/Shift/Cmd while gesturing
- **Configurable min trigger distance** — adjustable 8–80pt slider to avoid accidental right-click triggers
- **6 action types** — keyboard shortcut (CGEvent key simulation), open URL, open application, shell script (`/bin/zsh`), AppleScript, and 16 built-in system actions
- **System actions** — window management (maximize/center/fullscreen/minimize via AX API → AppleScript → CGEvent), volume/brightness/media, mission control, app expose, show desktop, lock screen, sleep display, spotlight, force quit
- **Run as Administrator** — toggle per shell script action, uses AppleScript `with administrator privileges`
- **Edge scroll** — scroll at screen edges (within 24pt) on any display to trigger actions
- **Gesture library** — 24 built-in presets (Navigation, Clipboard, Tabs, Applications, Window, Media, System) — browse and add
- **Conflict detection** — warns when editing a gesture too similar to an existing rule with overlapping scope
- **Practice mode** — draw in the gesture canvas to test recognition without saving
- **Blocked apps** — disable gestures for specific applications (games, drawing apps, etc.)
- **Synthetic click passthrough** — replays a normal right click when movement is too small; uses a marker to avoid re-intercepting its own events
- **Multi-monitor** — overlays, edge detection, and coordinate conversion correctly handle multiple displays
- **Localization** — full English and Simplified Chinese; Chinese is the default
- **Logging** — structured file logger (6 levels: off/trace/debug/info/warning/error) to `~/Library/Application Support/Strokly/Logs/strokly.log`
- **Debug tools** — "Show Edge Zones" visualizes edge detection thresholds; "Debug Logging" enables per-event logging
- **Single instance** — enforces only one running instance
- **Launch at login** — via `SMAppService` (macOS 13+)

## Architecture

```
StroklyApp.swift (@main)
    │
StroklyCore ──────────────────────────────
  ├── Views (SwiftUI)                     │
  │   ContentView, RuleEditorView,       │
  │   SettingsView, GestureLibraryView,   │
  │   MenuBarContentView, …              │
  ├── Stores (ObservableObject)           │
  │   RuleStore → Rules.json             │
  │   AppSettingsStore → UserDefaults    │
  ├── Services                            │
  │   GestureEngine (orchestrator)        │
  │   GestureEventMonitor (CGEvent tap)   │
  │   GestureRecognizer (path→tokens)     │
  │   RuleMatcher (tokens/→rule)          │
  │   ActionExecutor (key/URL/shell/AX)   │
  │   EdgeScrollDetector                  │
  │   GestureOverlayWindow (trail draw)   │
  │   GestureTipWindow (HUD popup)        │
  │   ScreenCoordinateConverter           │
  ├── Models                              │
  │   GestureRule, GestureSignature,      │
  │   GestureDirection, GestureTemplate,  │
  │   GestureAction, KeyboardShortcutSpec │
  └── Support                             │
      L10n (localization), StroklyLogger  │
```

## Run

```bash
./script/build_and_run.sh
```

| Argument | Description |
|---|---|
| `run` (default) | Build and launch |
| `--verify` | Build, launch, confirm process is alive |
| `--debug` | Build and attach lldb |
| `--logs` | Build, launch, stream `log stream` |
| `--package` | Build `.pkg` + `.dmg` in `dist/` |
| `--generate-icon` | Regenerate app icon only |

The build script ad-hoc signs the bundle; it is not Developer ID notarized.

## Checks

```bash
swift run StroklyCoreChecks
```

26+ unit-style checks (direction recognition, signature parsing, template normalization, template matching, rule matching priority, conflict detection, edge scroll, localization) — no XCTest dependency required.

## Permission

Global mouse monitoring and synthetic keyboard shortcuts require macOS **Accessibility** permission. On first launch, an onboarding sheet guides you through granting it. You can also use the menu bar item **Grant Accessibility Access**.

## Requirements

- macOS 13.0+ (Ventura)
- Xcode 15+ or Command Line Tools (for building)
- No external dependencies (pure Swift, SwiftPM)

## License

MIT