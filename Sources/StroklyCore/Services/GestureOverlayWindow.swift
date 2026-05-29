import AppKit
import CoreGraphics
import Foundation
import QuartzCore

@MainActor
public final class GestureOverlayWindow {
    private var windowMap: [CGDirectDisplayID: (window: NSWindow, view: GestureOverlayView)] = [:]
    private var cachedMappings: [ScreenCoordinateConverter.DisplayMapping] = []
    private var activeDisplayID: CGDirectDisplayID?

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

        // Fast path: if we already know which display, use it
        let displayID: CGDirectDisplayID
        if let cached = activeDisplayID,
           let mapping = cachedMappings.first(where: { $0.displayID == cached }),
           mapping.containsCGPoint(points.last!) {
            displayID = cached
        } else {
            guard let mapping = cachedMappings.first(where: { $0.containsCGPoint(points.last!) }) else {
                return
            }
            displayID = mapping.displayID
            activeDisplayID = displayID
        }

        guard let mapping = cachedMappings.first(where: { $0.displayID == displayID }) else { return }

        let appKitPoints = points.map(mapping.appKitPoint(fromCGPoint:))

        // Hide other displays
        for (id, entry) in windowMap where id != displayID {
            entry.window.orderOut(nil)
            windowMap[id] = nil
        }

        if let entry = windowMap[displayID] {
            entry.view.points = appKitPoints
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

            let view = GestureOverlayView(frame: CGRect(origin: .zero, size: mapping.appKitFrame.size))
            view.desktopFrame = mapping.appKitFrame
            view.points = appKitPoints
            overlayWindow.contentView = view
            overlayWindow.orderFrontRegardless()
            windowMap[displayID] = (overlayWindow, view)
        }
    }

    public func hide() {
        for (_, entry) in windowMap {
            entry.window.orderOut(nil)
            entry.view.clearDrawing()
        }
        windowMap.removeAll()
        activeDisplayID = nil
    }

    public func refreshScreens() {
        cachedMappings = ScreenCoordinateConverter().mappings
        activeDisplayID = nil
    }
}

private final class GestureOverlayView: NSView {
    var points: [CGPoint] = [] {
        didSet { scheduleRedraw() }
    }

    var desktopFrame: CGRect = .zero
    private var lastRedrawTime: CFTimeInterval = 0
    private var pendingRedraw = false
    private var traceLayer: CAShapeLayer?
    private var lastDrawnCount: Int = 0

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
    }

    func clearDrawing() {
        points = []
        lastDrawnCount = 0
        traceLayer?.path = nil
        traceLayer?.removeFromSuperlayer()
        traceLayer = nil
    }

    private func scheduleRedraw() {
        let now = CACurrentMediaTime()
        if now - lastRedrawTime >= 0.016 {
            lastRedrawTime = now
            needsDisplay = true
        } else if !pendingRedraw {
            pendingRedraw = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                guard let self else { return }
                self.pendingRedraw = false
                self.lastRedrawTime = CACurrentMediaTime()
                self.needsDisplay = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard points.count > 1 else { return }

        let converted = points.map(convertPointToView)

        if traceLayer == nil {
            let layer = CAShapeLayer()
            layer.strokeColor = NSColor.systemBlue.cgColor
            layer.fillColor = NSColor.clear.cgColor
            layer.lineWidth = 4
            layer.lineCap = .round
            layer.lineJoin = .round
            self.layer?.addSublayer(layer)
            traceLayer = layer
            lastDrawnCount = 0
        }

        // Incremental path update: only append new segments
        let path: CGMutablePath
        if lastDrawnCount > 0 && lastDrawnCount <= converted.count {
            path = (traceLayer?.path?.mutableCopy()) ?? CGMutablePath()
            for i in lastDrawnCount..<converted.count {
                if i == 0 {
                    path.move(to: converted[i])
                } else {
                    path.addLine(to: converted[i])
                }
            }
        } else {
            path = CGMutablePath()
            path.move(to: converted[0])
            for point in converted.dropFirst() {
                path.addLine(to: point)
            }
        }

        traceLayer?.path = path
        lastDrawnCount = converted.count

        // Draw endpoint dot
        if let end = converted.last {
            let dot = NSBezierPath(ovalIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10))
            NSColor.systemBlue.withAlphaComponent(0.95).setFill()
            dot.fill()
        }
    }

    private func convertPointToView(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - desktopFrame.minX,
            y: desktopFrame.maxY - point.y
        )
    }
}
