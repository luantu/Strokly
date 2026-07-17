import AppKit
import CoreGraphics
import Foundation

public struct GestureCapture: Equatable {
    public var signature: GestureSignature
    public var template: GestureTemplate
    public var points: [CGPoint]
    public var startedAt: Date
    public var endedAt: Date
    public var triggerButton: TriggerButton
    public var activeModifiers: [KeyboardModifier]
    public var noiseCount: Int
}

public enum GestureEventMonitorError: Error, LocalizedError {
    case cannotCreateEventTap

    public var errorDescription: String? {
        switch self {
        case .cannotCreateEventTap:
            return "Unable to create the global mouse event tap. Grant Accessibility access and try again."
        }
    }
}

public struct EdgeScrollCapture: Equatable {
    public var edge: ScreenEdge
    public var direction: ScrollDirection
    public var point: CGPoint
    public var activeModifiers: [KeyboardModifier]
}

public final class GestureEventMonitor {
    public var onTraceChanged: ([CGPoint]) -> Void = { _ in }
    public var onGesture: (GestureCapture) -> Void = { _ in }
    public var onEdgeScroll: (EdgeScrollCapture) -> Void = { _ in }
public private(set) var activeButton: TriggerButton = .rightMouse

    public var recognizer: GestureRecognizer
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var points: [CGPoint] = []
    private var startedAt = Date()
    private let syntheticMarker: Int64 = 0x5354524F4B4C59
    private let edgeThreshold: CGFloat = 24
    private var lastDispatchedPoint: CGPoint = .zero
    private let minMoveThreshold: CGFloat = 5

    public init(recognizer: GestureRecognizer = GestureRecognizer()) {
        self.recognizer = recognizer
    }

    public var isRunning: Bool {
        eventTap != nil
    }

    public func start() throws {
        guard eventTap == nil else {
            return
        }

        let mask =
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: gestureEventTapCallback,
            userInfo: refcon
        ) else {
            throw GestureEventMonitorError.cannotCreateEventTap
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        StroklyLogger.shared.info("monitor.start", [
            "edgeThreshold": "\(edgeThreshold)",
            "displays": "\(EdgeScrollDetector.activeDisplays().count)"
        ])
    }

    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
        points = []
        StroklyLogger.shared.info("monitor.stop")
        DispatchQueue.main.async { [onTraceChanged] in
            onTraceChanged([])
        }
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .rightMouseDown, .otherMouseDown:
            let button = triggerButton(for: type, event: event)
            guard button != nil else { break }
            activeButton = button!
            startedAt = Date()
            lastDispatchedPoint = event.location
            points = [event.location]
            DispatchQueue.main.async { [onTraceChanged, points] in
                onTraceChanged(points)
            }
            return nil
        case .rightMouseDragged, .otherMouseDragged:
            guard !points.isEmpty else {
                return Unmanaged.passUnretained(event)
            }

            let loc = event.location
            let dx = loc.x - lastDispatchedPoint.x
            let dy = loc.y - lastDispatchedPoint.y
            if dx * dx + dy * dy >= minMoveThreshold * minMoveThreshold {
                points.append(loc)
                lastDispatchedPoint = loc
                let snapshot = points
                DispatchQueue.main.async { [onTraceChanged] in
                    onTraceChanged(snapshot)
                }
            } else {
                points.append(loc)
            }
            return nil
        case .rightMouseUp, .otherMouseUp:
            guard !points.isEmpty else {
                return Unmanaged.passUnretained(event)
            }

            points.append(event.location)
            finishGesture(modifiers: activeModifiers(from: event))
            return nil
        case .scrollWheel:
            if handleEdgeScroll(event: event) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func triggerButton(for type: CGEventType, event: CGEvent) -> TriggerButton? {
        if type == .rightMouseDown { return .rightMouse }
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        switch buttonNumber {
        case 2: return .middleMouse
        case 3: return .button4
        case 4: return .button5
        default: return nil
        }
    }

    private func activeModifiers(from event: CGEvent) -> [KeyboardModifier] {
        let flags = event.flags
        var mods: [KeyboardModifier] = []
        if flags.contains(.maskControl) { mods.append(.control) }
        if flags.contains(.maskAlternate) { mods.append(.option) }
        if flags.contains(.maskShift) { mods.append(.shift) }
        if flags.contains(.maskCommand) { mods.append(.command) }
        return mods
    }

    private func handleEdgeScroll(event: CGEvent) -> Bool {
        let cgPoint = event.location
        let deltaY = scrollDeltaY(from: event)
        guard deltaY != 0 else {
            StroklyLogger.shared.trace("edgeScroll.ignore.zeroDelta", [
                "x": String(format: "%.1f", cgPoint.x),
                "y": String(format: "%.1f", cgPoint.y)
            ])
            return false
        }

        let direction: ScrollDirection = deltaY > 0 ? .up : .down
        let displays = EdgeScrollDetector.activeDisplays()

        StroklyLogger.shared.trace("edgeScroll.event", [
            "x": String(format: "%.1f", cgPoint.x),
            "y": String(format: "%.1f", cgPoint.y),
            "deltaY": String(format: "%.3f", deltaY),
            "direction": direction.rawValue,
            "displayCount": "\(displays.count)"
        ])

        guard let edge = EdgeScrollDetector.edge(
            for: cgPoint,
            displays: displays,
            threshold: edgeThreshold
        ) else {
            StroklyLogger.shared.debug("edgeScroll.noEdge", [
                "x": String(format: "%.1f", cgPoint.x),
                "y": String(format: "%.1f", cgPoint.y),
                "deltaY": String(format: "%.3f", deltaY)
            ])
            return false
        }

        let capture = EdgeScrollCapture(
            edge: edge,
            direction: direction,
            point: cgPoint,
            activeModifiers: activeModifiers(from: event)
        )
        DispatchQueue.main.async { [onEdgeScroll] in
            onEdgeScroll(capture)
        }
        StroklyLogger.shared.debug("edgeScroll.detected", [
            "edge": edge.rawValue,
            "direction": direction.rawValue,
            "x": String(format: "%.1f", cgPoint.x),
            "y": String(format: "%.1f", cgPoint.y)
        ])
        return true
    }

    private func scrollDeltaY(from event: CGEvent) -> Double {
        let pointDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        if pointDelta != 0 {
            return pointDelta
        }

        let fixedDelta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        if fixedDelta != 0 {
            return fixedDelta
        }

        return Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
    }

    private func finishGesture(modifiers: [KeyboardModifier]) {
        let capturedPoints = points
        let finishedAt = Date()
        let captureStartedAt = startedAt
        let button = activeButton
        points = []

        if let candidate = recognizer.analyze(capturedPoints) {
            StroklyLogger.shared.debug("gesture.finish.recognized", [
                "points": "\(capturedPoints.count)",
                "durationMs": "\(Int(finishedAt.timeIntervalSince(captureStartedAt) * 1000))",
                "trigger": button.rawValue,
                "signature": candidate.signature.compactText
            ])
            let capture = GestureCapture(
                signature: candidate.signature,
                template: candidate.template,
                points: capturedPoints,
                startedAt: captureStartedAt,
                endedAt: Date(),
                triggerButton: button,
                activeModifiers: modifiers,
                noiseCount: candidate.noiseCount
            )
            DispatchQueue.main.async { [onTraceChanged, onGesture] in
                onTraceChanged([])
                onGesture(capture)
            }
        } else if let firstPoint = capturedPoints.first {
            StroklyLogger.shared.debug("gesture.finish.noMatch", ["points": "\(capturedPoints.count)"])
            DispatchQueue.main.async { [onTraceChanged] in
                onTraceChanged([])
            }
            postSyntheticClick(at: firstPoint, button: button)
        }
    }

    private func postSyntheticClick(at point: CGPoint, button: TriggerButton) {
        let source = CGEventSource(stateID: .hidSystemState)
        let mouseButton: CGMouseButton
        let downType: CGEventType
        let upType: CGEventType
        switch button {
        case .rightMouse:
            mouseButton = .right; downType = .rightMouseDown; upType = .rightMouseUp
        case .middleMouse:
            mouseButton = .center; downType = .otherMouseDown; upType = .otherMouseUp
        case .button4:
            mouseButton = CGMouseButton(rawValue: 3)!; downType = .otherMouseDown; upType = .otherMouseUp
        case .button5:
            mouseButton = CGMouseButton(rawValue: 4)!; downType = .otherMouseDown; upType = .otherMouseUp
        case .edgeScroll:
            mouseButton = .right; downType = .rightMouseDown; upType = .rightMouseUp
        }
        let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: mouseButton)
        let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: mouseButton)

        down?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

private let gestureEventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<GestureEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return monitor.handle(proxy: proxy, type: type, event: event)
}
