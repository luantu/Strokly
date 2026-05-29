import AppKit
import CoreGraphics
import Foundation

@MainActor
public final class ActionExecutor {
    public init() {}

    public func execute(_ action: GestureAction, focusPoint: CGPoint? = nil) {
        if action.focusVisibleWindowBeforeExecution {
            focusVisibleWindow(at: focusPoint)
        }

        switch action.kind {
        case .keyStroke:
            guard let shortcut = action.keyShortcut else { return }
            send(shortcut)
        case .openURL:
            openURL(action.value)
        case .openApplication:
            openApplication(action.value)
        case .shellScript:
            runShellScript(action.value)
        case .appleScript:
            runAppleScript(action.value)
        case .systemAction:
            if let sys = action.systemAction {
                executeSystemAction(sys)
            }
        }
    }

    public func executeSystemAction(_ action: SystemAction) {
        switch action {
        case .maximizeWindow:
            guard let screen = screenContainingFrontWindow() ?? NSScreen.main else { return }
            let visibleFrame = screen.visibleFrame
            let converter = ScreenCoordinateConverter()
            let cgOrigin = CGPoint(x: visibleFrame.origin.x, y: converter.appKitDesktopFrame.maxY - visibleFrame.origin.y - visibleFrame.height)
            let targetFrame = CGRect(origin: cgOrigin, size: visibleFrame.size)
            maximizeFrontWindow(to: targetFrame)

        case .centerWindow:
            guard let screen = screenContainingFrontWindow() ?? NSScreen.main else { return }
            let sf = screen.visibleFrame
            guard let win = frontWindowFrame() else { return }
            let converter = ScreenCoordinateConverter()
            let cgMidY = converter.appKitDesktopFrame.maxY - sf.midY
            let x = sf.midX - win.width / 2
            let y = cgMidY - win.height / 2
            moveFrontWindow(to: CGPoint(x: x, y: y))

        case .fullscreen:
            sendKey(code: 3, flags: [.maskCommand, .maskControl])

        case .minimizeWindow:
            minimizeFrontWindow()

        // Volume — via System Events key simulation (triggers system HUD)
        case .volumeUp:
            runShellScript("osascript -e 'tell application \"System Events\" to key code 111'")

        case .volumeDown:
            runShellScript("osascript -e 'tell application \"System Events\" to key code 103'")

        case .volumeMute:
            runShellScript("osascript -e 'tell application \"System Events\" to key code 109'")

        // Brightness — via osascript (key codes unreliable on modern Macs)
        case .brightnessUp:
            runShellScript("osascript -e 'tell application \"System Events\" to key code 144'")

        case .brightnessDown:
            runShellScript("osascript -e 'tell application \"System Events\" to key code 145'")

        // System — CGEvent key simulation
        case .showDesktop:
            sendKey(code: 103, flags: [.maskCommand]) // F11

        case .missionControl:
            sendKey(code: 126, flags: [.maskControl]) // Up Arrow + Ctrl

        case .appExpose:
            sendKey(code: 125, flags: [.maskControl]) // Down Arrow + Ctrl

        case .spotlight:
            sendKey(code: 49, flags: [.maskCommand]) // Space + Cmd

        case .forceQuit:
            sendKey(code: 53, flags: [.maskCommand, .maskAlternate]) // Esc + Cmd+Option

        case .lockScreen:
            runShellScript("osascript -e 'tell application \"System Events\" to keystroke \"q\" using {command down, control down}'")

        case .sleepDisplay:
            runShellScript("pmset displaysleepnow")
        }
    }

    // MARK: - Window Helpers (via AX API)

    private func focusVisibleWindow(at point: CGPoint?) {
        let targetPoint = point ?? CGEvent(source: nil)?.location ?? .zero
        StroklyLogger.shared.debug("action.focusVisibleWindow.begin", [
            "x": String(format: "%.1f", targetPoint.x),
            "y": String(format: "%.1f", targetPoint.y)
        ])

        guard let candidate = visibleWindowCandidate(at: targetPoint) else {
            StroklyLogger.shared.warning("action.focusVisibleWindow.noCandidate")
            return
        }

        guard let app = NSRunningApplication(processIdentifier: candidate.pid) else {
            StroklyLogger.shared.warning("action.focusVisibleWindow.noRunningApp", ["pid": "\(candidate.pid)"])
            return
        }

        app.activate(options: [.activateIgnoringOtherApps])
        let appRef = AXUIElementCreateApplication(candidate.pid)
        if let window = axWindow(in: appRef, matching: candidate.bounds) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, window)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }

        StroklyLogger.shared.info("action.focusVisibleWindow.done", [
            "pid": "\(candidate.pid)",
            "app": app.localizedName ?? "",
            "owner": candidate.ownerName
        ])
    }

    private struct WindowCandidate {
        var pid: pid_t
        var ownerName: String
        var bounds: CGRect
    }

    private func visibleWindowCandidate(at point: CGPoint) -> WindowCandidate? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        for item in list {
            let layer = item[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            let pid = item[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard pid != 0, pid != currentPID else { continue }
            let alpha = item[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0 else { continue }
            guard let boundsDictionary = item[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.width > 20,
                  bounds.height > 20,
                  bounds.contains(point) else {
                continue
            }

            return WindowCandidate(
                pid: pid,
                ownerName: item[kCGWindowOwnerName as String] as? String ?? "",
                bounds: bounds
            )
        }

        return nil
    }

    private func axWindow(in app: AXUIElement, matching bounds: CGRect) -> AXUIElement? {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }

        return windows.min { left, right in
            frameDistance(axFrame(left), bounds) < frameDistance(axFrame(right), bounds)
        }
    }

    private func axFrame(_ window: AXUIElement) -> CGRect {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)

        var point = CGPoint.zero
        var size = CGSize.zero
        if let posRef {
            AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        }
        if let sizeRef {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: point, size: size)
    }

    private func frameDistance(_ left: CGRect, _ right: CGRect) -> CGFloat {
        abs(left.minX - right.minX) +
            abs(left.minY - right.minY) +
            abs(left.width - right.width) +
            abs(left.height - right.height)
    }

    private func minimizeFrontWindow() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier

        // Strategy 1: AX API — press the minimize button
        let appRef = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let window = windowRef {
            let win = window as! AXUIElement
            var buttonRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(win, kAXMinimizeButtonAttribute as CFString, &buttonRef) == .success,
               let button = buttonRef {
                let result = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
                if result == .success { return }
            }
        }

        // Strategy 2: AppleScript — System Events miniaturize
        let script = """
        tell application "System Events"
            set frontApp to first application process whose unix id is \(pid)
            tell frontApp
                if (count of windows) > 0 then
                    set frontWindow to front window
                    miniaturize frontWindow
                end if
            end tell
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if error == nil { return }

        // Strategy 3: CGEvent — Cmd+M
        sendKey(code: 46, flags: [.maskCommand])
    }

    private func screenContainingFrontWindow() -> NSScreen? {
        guard let frame = frontWindowFrame() else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let converter = ScreenCoordinateConverter()
        let appKitCenter = converter.appKitPoint(fromCGPoint: center)
        return NSScreen.screens.first { $0.frame.contains(appKitCenter) }
    }

    private func frontWindowFrame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return nil }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef)

        guard let posVal = posRef, let sizeVal = sizeRef else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private func moveFrontWindow(to point: CGPoint) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return }

        var p = point
        if let value = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, value)
        }
    }

    private func maximizeFrontWindow(to frame: CGRect) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return }
        let win = window as! AXUIElement

        // Strategy 1: AX API — set position then size
        var origin = frame.origin
        var size = frame.size
        var posOk = false
        var sizeOk = false
        if let posVal = AXValueCreate(.cgPoint, &origin) {
            posOk = AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, posVal) == .success
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            sizeOk = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeVal) == .success
        }
        if posOk && sizeOk { return }

        // Strategy 2: AppleScript via System Events
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        let script = """
        tell application "System Events"
            set frontApp to first application process whose unix id is \(pid)
            tell frontApp
                if (count of windows) > 0 then
                    set frontWindow to front window
                    set position of frontWindow to {\(Int(sf.origin.x)), \(Int(sf.origin.y))}
                    set size of frontWindow to {\(Int(sf.width)), \(Int(sf.height))}
                end if
            end tell
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    private func resizeFrontWindow(to frame: CGRect) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return }
        let win = window as! AXUIElement

        // Set position first, then size — prevents race condition
        var origin = frame.origin
        if let posVal = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, posVal)
        }
        var size = frame.size
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    // MARK: - CGEvent Key Simulation

    private func sendKey(code: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard Shortcut

    private func send(_ shortcut: KeyboardShortcutSpec) {
        guard let keyCode = shortcut.keyCode else { return }
        sendKey(code: keyCode, flags: shortcut.flags)
    }

    // MARK: - General

    private func openURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openApplication(_ value: String) {
        guard !value.isEmpty else { return }
        let url = URL(fileURLWithPath: value)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let appName = value.hasSuffix(".app") ? value : "\(value).app"
        let candidates = [
            URL(fileURLWithPath: "/Applications").appendingPathComponent(appName),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").appendingPathComponent(appName)
        ]
        guard let appURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private func runShellScript(_ script: String) {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        try? process.run()
    }

    private func runAppleScript(_ script: String) {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
}
