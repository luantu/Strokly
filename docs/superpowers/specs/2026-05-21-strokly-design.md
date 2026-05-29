# Strokly Design

## Goal

Build a macOS utility for right-button mouse gestures. The first version should
capture right-button drag gestures globally, normalize the path into direction
tokens, match those tokens against user-editable rules, and execute an assigned
action.

## Product Shape

The app is a regular SwiftUI macOS app with a menu bar extra. Users can start or
stop monitoring, request Accessibility permission, edit gesture rules, and see
the last recognized gesture/action.

## Core Behavior

- Right mouse down starts gesture tracking.
- Right mouse drag records pointer points and shows a lightweight overlay.
- Right mouse up recognizes the gesture.
- If movement is too small, Strokly replays a normal right click.
- If a gesture is recognized, Strokly looks for an enabled app-specific rule
  first, then falls back to a global rule.

## Actions

The first implementation supports keyboard shortcuts, URLs, application launch,
shell scripts, and AppleScript. Keyboard shortcut sending and event monitoring
require Accessibility permission.

## Architecture

- `StroklyCore/Models`: gesture signatures, rules, scopes, and action models.
- `StroklyCore/Services`: recognition, matching, event tap, overlay, permission,
  and action execution.
- `StroklyCore/Stores`: JSON-backed user rules in Application Support.
- `StroklyCore/Views`: SwiftUI rule editor, sidebar, and menu bar content.
- `StroklyApp`: app entrypoint and macOS lifecycle.

## Verification

The current Command Line Tools install does not include XCTest or Swift Testing,
so core behavior is covered by the `StroklyCoreChecks` executable target.
