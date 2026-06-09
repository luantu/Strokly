import AppKit
import CoreGraphics
import Foundation
import QuartzCore

@MainActor
public final class GestureOverlayWindow {
    private var windowMap: [CGDirectDisplayID: (window: NSWindow, view: OverlayContentView)] = [:]
    private var cachedMappings: [ScreenCoordinateConverter.DisplayMapping] = []
    private var activeDisplayID: CGDirectDisplayID?
    private var lastPointCount: Int = 0

    public init() {}

    public func update(points: [CGPoint]) {
        guard !points.isEmpty else {
            hide()
            return
        }

        if cachedMappings.isEmpty {
            let converter = ScreenCoordinateConverter()
            cachedMappings = converter.mappings
        }

        let displayID = findDisplay(for: points.last!)
        guard let mapping = cachedMappings.first(where: { $0.displayID == displayID }) else { return }
        activeDisplayID = displayID

        for (id, entry) in windowMap where id != displayID {
            entry.window.orderOut(nil)
            windowMap[id] = nil
        }

        if let entry = windowMap[displayID] {
            entry.view.appendPoints(points, from: lastPointCount, cgBounds: mapping.cgBounds)
            if !entry.window.isVisible {
                entry.window.setFrame(mapping.appKitFrame, display: false)
                entry.window.orderFrontRegardless()
            }
        } else {
            let overlayWindow = NSWindow(
                contentRect: mapping.appKitFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            overlayWindow.isOpaque = false
            overlayWindow.backgroundColor = .clear
            overlayWindow.ignoresMouseEvents = true
            overlayWindow.level = .screenSaver
            overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            overlayWindow.hasShadow = false

            let view = OverlayContentView(frame: CGRect(origin: .zero, size: mapping.appKitFrame.size))
            view.appendPoints(points, from: 0, cgBounds: mapping.cgBounds)
            overlayWindow.contentView = view
            overlayWindow.orderFrontRegardless()
            windowMap[displayID] = (overlayWindow, view)
        }

        lastPointCount = points.count
    }

    public func hide() {
        for (_, entry) in windowMap {
            entry.window.orderOut(nil)
            entry.view.clearDrawing()
        }
        windowMap.removeAll()
        activeDisplayID = nil
        lastPointCount = 0
    }

    public func refreshScreens() {
        cachedMappings = ScreenCoordinateConverter().mappings
        activeDisplayID = nil
    }

    private func findDisplay(for point: CGPoint) -> CGDirectDisplayID {
        if let cached = activeDisplayID,
           let mapping = cachedMappings.first(where: { $0.displayID == cached }),
           mapping.containsCGPoint(point) {
            return cached
        }
        return cachedMappings.first(where: { $0.containsCGPoint(point) })?.displayID
            ?? cachedMappings.first!.displayID
    }
}

private final class OverlayContentView: NSView {
    private let traceLayer: CAShapeLayer = {
        let l = CAShapeLayer()
        l.strokeColor = NSColor.systemBlue.cgColor
        l.fillColor = NSColor.clear.cgColor
        l.lineWidth = 4
        l.lineCap = .round
        l.lineJoin = .round
        return l
    }()

    private let dotLayer: CAShapeLayer = {
        let l = CAShapeLayer()
        l.fillColor = NSColor.systemBlue.withAlphaComponent(0.95).cgColor
        return l
    }()

    private var cgBounds: CGRect = .zero

    override var isFlipped: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(traceLayer)
        layer?.addSublayer(dotLayer)
    }

    required init?(coder: NSCoder) { nil }

    func appendPoints(_ cgPoints: [CGPoint], from startIdx: Int, cgBounds: CGRect) {
        self.cgBounds = cgBounds
        guard startIdx < cgPoints.count else { return }

        let path: CGMutablePath
        if startIdx > 0, let existing = traceLayer.path, let copy = existing.mutableCopy() {
            path = copy
        } else {
            path = CGMutablePath()
            path.move(to: viewPoint(cgPoints[0], cgBounds: cgBounds))
        }

        for i in Swift.max(startIdx, 1)..<cgPoints.count {
            path.addLine(to: viewPoint(cgPoints[i], cgBounds: cgBounds))
        }

        traceLayer.path = path

        if let last = cgPoints.last {
            let vp = viewPoint(last, cgBounds: cgBounds)
            let dot = CGMutablePath()
            dot.addEllipse(in: CGRect(x: vp.x - 5, y: vp.y - 5, width: 10, height: 10))
            dotLayer.path = dot
        }
    }

    func clearDrawing() {
        traceLayer.path = nil
        dotLayer.path = nil
    }

    private func viewPoint(_ p: CGPoint, cgBounds: CGRect) -> CGPoint {
        CGPoint(x: p.x - cgBounds.minX, y: p.y - cgBounds.minY)
    }
}