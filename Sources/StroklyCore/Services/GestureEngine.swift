import AppKit
import Combine
import Foundation

@MainActor
public final class GestureEngine: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var lastGesture = "None"
    @Published public private(set) var lastAction = "None"
    @Published public private(set) var lastError: String?
    @Published public var debugMode = false

    private let ruleStore: RuleStore
    private let settingsStore: AppSettingsStore
    public let monitor: GestureEventMonitor
    private let executor: ActionExecutor
    private let overlay: GestureOverlayWindow
    private let tipWindow: GestureTipWindow
    public let debugWindow = EdgeScrollDebugWindow()
    private let edgeScrollThrottleInterval: TimeInterval = 0.15
    private var lastEdgeScrollTime: Date = .distantPast
    private var previewRecognizer = GestureRecognizer()

    private var pendingMatch: (rule: GestureRule, capture: GestureCapture)?
    private var hasReachedMinDistance = false

    public init(ruleStore: RuleStore, settingsStore: AppSettingsStore) {
        self.ruleStore = ruleStore
        self.settingsStore = settingsStore
        self.monitor = GestureEventMonitor()
        self.executor = ActionExecutor()
        self.overlay = GestureOverlayWindow()
        self.tipWindow = GestureTipWindow()

        let d = settingsStore.minGestureDistance
        monitor.recognizer.minSegmentLength = d
        monitor.recognizer.minPathLength = d
        previewRecognizer.minSegmentLength = d
        previewRecognizer.minPathLength = d

        monitor.onTraceChanged = { [weak self] points in
            guard let self else {
                self?.overlay.hide()
                return
            }
            if points.isEmpty {
                self.overlay.hide()
                self.hasReachedMinDistance = false
                return
            }
            guard !self.isFrontmostAppBlocked() else {
                self.overlay.hide()
                self.pendingMatch = nil
                return
            }

            if !self.hasReachedMinDistance {
                self.hasReachedMinDistance = self.isAboveMinDistance(points)
            }

            if self.hasReachedMinDistance {
                self.overlay.update(points: points)
                self.updatePreview(points: points)
            }
        }

        monitor.onGesture = { [weak self] capture in
            self?.handle(capture)
        }

        monitor.onEdgeScroll = { [weak self] capture in
            self?.handleEdgeScroll(capture)
        }
    }

    private func isAboveMinDistance(_ points: [CGPoint]) -> Bool {
        guard points.count > 1 else { return false }
        let first = points.first!
        let last = points.last!
        let dx = last.x - first.x
        let dy = last.y - first.y
        return hypot(dx, dy) >= settingsStore.minGestureDistance
    }

    private func updatePreview(points: [CGPoint]) {
        guard points.count > 1 else {
            pendingMatch = nil
            tipWindow.hide()
            return
        }

        let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let activeModifiers = currentModifiers()

        guard let signature = previewRecognizer.recognize(points),
              signature.directions.count >= 1 else {
            pendingMatch = nil
            tipWindow.hide()
            return
        }

        let triggerButton = monitor.activeButton

        guard let match = RuleMatcher.match(
            signature: signature,
            triggerButton: triggerButton,
            activeModifiers: activeModifiers,
            bundleIdentifier: bundleIdentifier,
            rules: ruleStore.rules
        ) else {
            pendingMatch = nil
            tipWindow.hide()
            return
        }

        pendingMatch = (match, GestureCapture(
            signature: signature,
            template: GestureTemplate(points: points),
            points: points,
            startedAt: Date(),
            endedAt: Date(),
            triggerButton: triggerButton,
            activeModifiers: activeModifiers
        ))

        if match.showTip, let last = points.last {
            tipWindow.show(title: match.name, detail: match.action.displaySummary, at: last)
        }
    }

    private func currentModifiers() -> [KeyboardModifier] {
        let flags = NSEvent.modifierFlags
        var mods: [KeyboardModifier] = []
        if flags.contains(.control) { mods.append(.control) }
        if flags.contains(.option) { mods.append(.option) }
        if flags.contains(.shift) { mods.append(.shift) }
        if flags.contains(.command) { mods.append(.command) }
        return mods
    }

    public var accessibilityTrusted: Bool {
        AccessibilityPermissionService.isTrusted
    }

    public func start() {
        guard !isRunning else {
            return
        }

        guard AccessibilityPermissionService.isTrusted else {
            lastError = "Accessibility permission is required before gesture monitoring can start."
            AccessibilityPermissionService.requestTrustPrompt()
            return
        }

        do {
            try monitor.start()
            isRunning = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func stop() {
        monitor.stop()
        overlay.hide()
        isRunning = false
    }

    public func toggle() {
        isRunning ? stop() : start()
    }

    public func refreshPermissionStatus() {
        objectWillChange.send()
    }

    private func isFrontmostAppBlocked() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return settingsStore.blockedAppBundleIDs.contains(bundleID)
    }

    private func handleEdgeScroll(_ capture: EdgeScrollCapture) {
        guard !isFrontmostAppBlocked() else { return }

        let now = Date()
        guard now.timeIntervalSince(lastEdgeScrollTime) >= edgeScrollThrottleInterval else { return }
        lastEdgeScrollTime = now

        let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let candidates = ruleStore.rules.filter {
            $0.isEnabled &&
                $0.triggerButton == .edgeScroll &&
                $0.edge == capture.edge &&
                $0.scrollDirection == capture.direction &&
                Set($0.modifierRequirements).isSubset(of: Set(capture.activeModifiers))
        }
        let rule = candidates.first {
            $0.scope.kind == .application && $0.scope.bundleIdentifier == (bundleIdentifier ?? "")
        } ?? candidates.first {
            $0.scope.kind == .global
        }
        guard let rule else {
            StroklyLogger.shared.warning("edgeScroll.noRule", [
                "edge": capture.edge.rawValue,
                "direction": capture.direction.rawValue,
                "candidateCount": "\(candidates.count)",
                "frontmost": bundleIdentifier ?? ""
            ])
            if debugMode {
                debugWindow.logScrollEvent(x: capture.point.x, y: capture.point.y, deltaY: 0,
                                           edge: capture.edge, distance: 0,
                                           detail: "no matching rule")
            }
            return
        }

        lastGesture = rule.displayTrigger
        lastAction = rule.name
        StroklyLogger.shared.info("edgeScroll.ruleMatched", [
            "rule": rule.name,
            "edge": capture.edge.rawValue,
            "direction": capture.direction.rawValue,
            "frontmost": bundleIdentifier ?? ""
        ])
        if debugMode {
            debugWindow.logScrollEvent(x: capture.point.x, y: capture.point.y, deltaY: 0,
                                       edge: capture.edge, distance: 0,
                                       detail: "rule: \(rule.name)")
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.executor.execute(rule.action, focusPoint: capture.point)
            if rule.showTip {
                var detail = rule.action.displaySummary
                if let sysAction = rule.action.systemAction,
                   let value = self.executor.currentValue(for: sysAction) {
                    detail = "\(detail) · \(value)"
                }
                self.tipWindow.show(title: rule.name, detail: detail, at: capture.point)
            }
        }
    }

    private func handle(_ capture: GestureCapture) {
        guard !isFrontmostAppBlocked() else { return }
        lastGesture = capture.signature.displayText.isEmpty ? "Custom Gesture" : capture.signature.displayText
        let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let usePendingTip = pendingMatch != nil

        guard let match = RuleMatcher.matchWithScore(
            template: capture.template,
            signature: capture.signature,
            triggerButton: capture.triggerButton,
            activeModifiers: capture.activeModifiers,
            bundleIdentifier: bundleIdentifier,
            rules: ruleStore.rules
        ) else {
            lastAction = "No matching rule"
            pendingMatch = nil
            tipWindow.hide()
            StroklyLogger.shared.warning("gesture.noRule", [
                "signature": capture.signature.compactText,
                "trigger": capture.triggerButton.rawValue,
                "frontmost": bundleIdentifier ?? ""
            ])
            return
        }

        let rule = match.rule
        lastAction = rule.name
        let focusPoint = capture.points.last
        pendingMatch = nil
        StroklyLogger.shared.info("gesture.ruleMatched", [
            "rule": rule.name,
            "score": String(format: "%.4f", match.score),
            "signature": capture.signature.compactText,
            "frontmost": bundleIdentifier ?? ""
        ])

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.executor.execute(rule.action, focusPoint: focusPoint)
            if rule.showTip {
                if usePendingTip {
                    self.tipWindow.updateDetail("\(rule.action.displaySummary) · match \(Int((1 - match.score).clamped(to: 0...1) * 100))%")
                } else {
                    self.tipWindow.show(
                        title: rule.name,
                        detail: "\(rule.action.displaySummary) · match \(Int((1 - match.score).clamped(to: 0...1) * 100))%",
                        at: focusPoint
                    )
                }
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
