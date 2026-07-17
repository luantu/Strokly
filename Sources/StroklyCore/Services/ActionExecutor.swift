import AppKit
import CoreGraphics
import Foundation

@MainActor
public final class ActionExecutor {
    private var focusPID: pid_t?

    public init() {}

    public func execute(_ action: GestureAction, focusPoint: CGPoint? = nil) {
        focusPID = nil
        let shouldFocus = action.focusVisibleWindowBeforeExecution
        StroklyLogger.shared.info("execute.begin", [
            "kind": "\(action.kind)",
            "focusEnabled": shouldFocus ? "yes" : "no",
            "hasFocusPoint": focusPoint != nil ? "yes" : "no"
        ])

        if shouldFocus {
            focusPID = focusVisibleWindow(at: focusPoint)
            StroklyLogger.shared.info("execute.focusResult", [
                "focusPID": focusPID.map { "\($0)" } ?? "nil"
            ])
        }

        switch action.kind {
        case .keyStroke:
            guard let shortcut = action.keyShortcut else { return }
            send(shortcut, to: focusPID)
        case .openURL:
            openURL(action.value)
        case .openApplication:
            openApplication(action.value)
        case .shellScript:
            runShellScript(action.value, asAdmin: action.runAsAdmin)
        case .appleScript:
            runAppleScript(action.value)
        case .systemAction:
            if let sys = action.systemAction {
                executeSystemAction(sys)
            }
        }
    }

    public func currentValue(for action: SystemAction) -> String? {
        switch action {
        case .volumeUp, .volumeDown:
            let script = "output volume of (get volume settings)"
            var error: NSDictionary?
            if let result = NSAppleScript(source: script)?.executeAndReturnError(&error) {
                return "\(result.int32Value)%"
            }
            return nil
        case .brightnessUp, .brightnessDown:
            return nil
        default:
            return nil
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

        // Volume — ±1 per notch
        case .volumeUp:
            runAppleScript("set volume output volume (output volume of (get volume settings) + 1)")

        case .volumeDown:
            runAppleScript("set volume output volume (output volume of (get volume settings) - 1)")

        case .volumeMute:
            runAppleScript("set volume output muted not (output muted of (get volume settings))")

        // Brightness — direct AppleScript
        case .brightnessUp:
            runAppleScript("tell application \"System Events\" to key code 144")

        case .brightnessDown:
            runAppleScript("tell application \"System Events\" to key code 145")

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
            runAppleScript("tell application \"System Events\" to keystroke \"q\" using {command down, control down}")

        case .sleepDisplay:
            runShellScript("pmset displaysleepnow")
        }
    }

    // MARK: - Window Helpers (via AX API)

    @discardableResult
    private func focusVisibleWindow(at point: CGPoint?) -> pid_t? {
        StroklyLogger.shared.info("action.focusVisibleWindow.begin", [
            "pointProvided": point != nil ? "yes" : "no"
        ])

        var targetPoint = point ?? CGEvent(source: nil)?.location ?? .zero
        StroklyLogger.shared.info("action.focusVisibleWindow.targetPoint", [
            "x": String(format: "%.1f", targetPoint.x),
            "y": String(format: "%.1f", targetPoint.y)
        ])

        var candidate = visibleWindowCandidate(at: targetPoint)
        StroklyLogger.shared.info("action.focusVisibleWindow.firstPass", [
            "found": candidate != nil ? "yes" : "no",
            "pid": candidate.map { "\($0.pid)" } ?? "nil",
            "owner": candidate?.ownerName ?? "nil"
        ])

        if candidate == nil {
            let newPoint = CGEvent(source: nil)?.location ?? targetPoint
            StroklyLogger.shared.info("action.focusVisibleWindow.retry", [
                "x": String(format: "%.1f", newPoint.x),
                "y": String(format: "%.1f", newPoint.y)
            ])
            targetPoint = newPoint
            candidate = visibleWindowCandidate(at: targetPoint)
            StroklyLogger.shared.info("action.focusVisibleWindow.secondPass", [
                "found": candidate != nil ? "yes" : "no",
                "pid": candidate.map { "\($0.pid)" } ?? "nil",
                "owner": candidate?.ownerName ?? "nil"
            ])
        }

        guard let candidate else {
            StroklyLogger.shared.warning("action.focusVisibleWindow.noCandidate")
            return nil
        }

        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        StroklyLogger.shared.info("action.focusVisibleWindow.found", [
            "pid": "\(candidate.pid)",
            "owner": candidate.ownerName,
            "frontmostPID": frontPID.map { "\($0)" } ?? "nil"
        ])

        guard let app = NSRunningApplication(processIdentifier: candidate.pid) else {
            StroklyLogger.shared.warning("action.focusVisibleWindow.noRunningApp", ["pid": "\(candidate.pid)"])
            return nil
        }

        StroklyLogger.shared.info("action.focusVisibleWindow.returning", [
            "pid": "\(candidate.pid)",
            "app": app.localizedName ?? ""
        ])

        return candidate.pid
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

        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        StroklyLogger.shared.info("visibleWindowCandidate.scan", [
            "totalWindows": "\(list.count)",
            "frontPID": frontPID.map { "\($0)" } ?? "nil"
        ])

        var nonFrontCandidates: [(WindowCandidate, CGFloat)] = []
        var frontHasWindowAtPoint = false

        for item in list {
            let layer = item[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            let pid = item[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard pid != 0 else { continue }
            let alpha = item[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0 else { continue }
            guard let boundsDictionary = item[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.width > 20,
                  bounds.height > 20 else {
                continue
            }

            let ownerName = item[kCGWindowOwnerName as String] as? String ?? ""
            let contains = bounds.contains(point)

            StroklyLogger.shared.info("visibleWindowCandidate.window", [
                "pid": "\(pid)",
                "owner": ownerName,
                "contains": contains ? "yes" : "no",
                "isFront": pid == frontPID ? "yes" : "no",
                "bounds": "\(Int(bounds.origin.x)),\(Int(bounds.origin.y)) \(Int(bounds.width))x\(Int(bounds.height))"
            ])

            if pid == frontPID {
                if contains {
                    StroklyLogger.shared.info("visibleWindowCandidate.frontWindowHit",
                        ["pid": "\(pid)", "owner": ownerName])
                    frontHasWindowAtPoint = true
                }
                continue
            }

            let candidate = WindowCandidate(pid: pid, ownerName: ownerName, bounds: bounds)

            if contains {
                // If the frontmost app already has a window at this point, user is gesturing on it
                if frontHasWindowAtPoint {
                    StroklyLogger.shared.info("visibleWindowCandidate.skippingBehindFront",
                        ["pid": "\(pid)", "owner": ownerName])
                    continue
                }
                StroklyLogger.shared.info("visibleWindowCandidate.exactMatch",
                    ["pid": "\(pid)", "owner": ownerName])
                return candidate
            }

            let distance = point.distanceSquared(to: bounds)
            nonFrontCandidates.append((candidate, distance))
        }

        // If the frontmost app has a window under the point, user is gesturing on it — do nothing
        if frontHasWindowAtPoint {
            StroklyLogger.shared.info("visibleWindowCandidate.gestureOnFrontmost",
                ["point": "\(String(format: "%.0f", point.x)),\(String(format: "%.0f", point.y))"])
            return nil
        }

        // Otherwise, return nearest non-frontmost window
        nonFrontCandidates.sort { $0.1 < $1.1 }
        if let best = nonFrontCandidates.first {
            StroklyLogger.shared.info("visibleWindowCandidate.nearest",
                ["pid": "\(best.0.pid)", "owner": best.0.ownerName,
                 "distance": String(format: "%.1f", sqrt(best.1))])
            return best.0
        }

        StroklyLogger.shared.info("visibleWindowCandidate.noneFound")
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

        // Set the entire frame atomically via AX frame attribute
        var cgFrame = frame
        if let frameVal = AXValueCreate(.cgRect, &cgFrame) {
            let result = AXUIElementSetAttributeValue(win, "AXFrame" as CFString, frameVal)
            if result == .success { return }
        }

        // Fallback: set size first, then position (order matters for some apps)
        var size = frame.size
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeVal)
        }
        var origin = frame.origin
        if let posVal = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, posVal)
        }

        // Strategy 2: AppleScript via System Events
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        let script = """
        tell application "System Events"
            set frontApp to first application process whose unix id is \(pid)
            tell frontApp
                if (count of windows) > 0 then
                    set frontWindow to front window
                    set size of frontWindow to {\(Int(sf.width)), \(Int(sf.height))}
                    set position of frontWindow to {\(Int(sf.origin.x)), \(Int(sf.origin.y))}
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

    private func sendKey(code: CGKeyCode, flags: CGEventFlags, to pid: pid_t? = nil) {
        StroklyLogger.shared.info("sendKey", [
            "keyCode": "\(code)", "flags": "\(flags.rawValue)",
            "targetPID": pid.map { "\($0)" } ?? "frontmost"
        ])

        if let pid, pid != ProcessInfo.processInfo.processIdentifier {
            // Activate the target app once before posting the key event
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.activate(options: [.activateIgnoringOtherApps])
                if let appName = app.localizedName {
                    let script = "tell application \"\(appName)\" to activate"
                    var error: NSDictionary?
                    NSAppleScript(source: script)?.executeAndReturnError(&error)
                }
                // Single short spin to let activation settle
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.08))
            }
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard Shortcut

    private func send(_ shortcut: KeyboardShortcutSpec, to pid: pid_t? = nil) {
        guard let keyCode = shortcut.keyCode else { return }
        sendKey(code: keyCode, flags: shortcut.flags, to: pid)
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

    private func runShellScript(_ script: String, asAdmin: Bool = false) {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if asAdmin {
            let escaped = script
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
            runAppleScript(appleScript)
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", script]
            try? process.run()
        }
    }

    private func runAppleScript(_ script: String) {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
}

private extension CGPoint {
    func distanceSquared(to rect: CGRect) -> CGFloat {
        let closestX = Swift.max(rect.minX, Swift.min(x, rect.maxX))
        let closestY = Swift.max(rect.minY, Swift.min(y, rect.maxY))
        let dx = x - closestX
        let dy = y - closestY
        return dx * dx + dy * dy
    }
}
