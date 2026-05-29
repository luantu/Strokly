# Strokly

Strokly is a SwiftUI macOS utility for right-button mouse gestures.

## What It Does

- Captures right-button drag gestures globally.
- Draws a lightweight gesture trail overlay.
- Normalizes movement into direction tokens: `U`, `D`, `L`, `R`.
- Matches app-specific rules before global rules.
- Executes keyboard shortcuts, URLs, app launches, shell scripts, or AppleScript.
- Replays a normal right click when movement is too small to count as a gesture.

## Run

```bash
./script/build_and_run.sh
```

Use `./script/build_and_run.sh --verify` to build, launch, and confirm the
process starts.

## Package

```bash
./script/build_and_run.sh --package
```

This creates `dist/Strokly.pkg`, which installs `Strokly.app` into
`/Applications`. The script also tries to create `dist/Strokly.dmg` for
drag-and-drop installation when `hdiutil` is available. The local build is
ad-hoc signed, not Developer ID notarized.

## Checks

This Command Line Tools install does not include `XCTest` or Swift Testing, so
the project uses a dependency-free check executable:

```bash
swift run StroklyCoreChecks
```

## Permission

Global mouse monitoring and synthetic keyboard shortcuts require macOS
Accessibility permission. Use the app menu item `Request Accessibility Access`,
then enable Strokly in System Settings.
