import AppKit
import CoreGraphics
import Foundation
import QuartzCore

@MainActor
public final class EdgeScrollDebugWindow {
    private var zoneWindows: [Int: NSWindow] = [:]
    private var hudWindow: NSWindow?
    private var hudLabel: NSTextField?
    private var isShowingZones = false
    private var isShowingHUD = false
    private var lastEventInfo: String = ""
    private var windowIDCounter = 0
    public var threshold: CGFloat = 24

    public init() {}

    public func showZones() {
        isShowingZones = true
        let displays = EdgeScrollDetector.activeDisplays()
        for display in displays {
            let bounds = display.bounds
            windowIDCounter += 1
            let wid = windowIDCounter
            let window = NSWindow(
                contentRect: bounds,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.hasShadow = false

            let view = EdgeZoneView(frame: CGRect(origin: .zero, size: bounds.size), threshold: threshold)
            window.contentView = view
            window.orderFrontRegardless()
            zoneWindows[wid] = window
        }
    }

    public func hideZones() {
        isShowingZones = false
        for (_, window) in zoneWindows {
            window.orderOut(nil)
        }
        zoneWindows.removeAll()
    }

    public func toggleZones() {
        isShowingZones ? hideZones() : showZones()
    }

    public var isShowing: Bool { isShowingZones || isShowingHUD }

    public func logScrollEvent(x: CGFloat, y: CGFloat, deltaY: Double, edge: ScreenEdge?, distance: CGFloat, detail: String = "") {
        let edgeStr = edge?.rawValue ?? "none"
        let info = detail.isEmpty
            ? String(format: "pos=(%.0f,%.0f) deltaY=%.2f edge=%@ dist=%.0f", x, y, deltaY, edgeStr, distance)
            : "\(detail) | \(String(format: "(%.0f,%.0f)", x, y)) edge=%@"
        lastEventInfo = info
        hudLabel?.stringValue = info
        hudLabel?.needsDisplay = true
    }
}

private final class EdgeZoneView: NSView {
    let threshold: CGFloat

    init(frame: NSRect, threshold: CGFloat) {
        self.threshold = threshold
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Top strip
        ctx.setFillColor(NSColor.systemYellow.withAlphaComponent(0.25).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: bounds.width, height: threshold))

        // Bottom strip
        ctx.setFillColor(NSColor.systemGreen.withAlphaComponent(0.25).cgColor)
        ctx.fill(CGRect(x: 0, y: bounds.height - threshold, width: bounds.width, height: threshold))

        // Left strip
        ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.25).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: threshold, height: bounds.height))

        // Right strip
        ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.25).cgColor)
        ctx.fill(CGRect(x: bounds.width - threshold, y: 0, width: threshold, height: bounds.height))
    }
}