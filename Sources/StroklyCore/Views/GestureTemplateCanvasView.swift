import AppKit
import SwiftUI

struct GestureTemplateCanvasView: NSViewRepresentable {
    @Binding var template: GestureTemplate
    var onCommit: ([CGPoint], GestureTemplate) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(template: $template, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> GestureTemplateCanvasNSView {
        let view = GestureTemplateCanvasNSView()
        view.onCommit = context.coordinator.commit(points:)
        return view
    }

    func updateNSView(_ nsView: GestureTemplateCanvasNSView, context: Context) {
        context.coordinator.template = $template
        context.coordinator.onCommit = onCommit
        nsView.template = template
    }

    final class Coordinator {
        var template: Binding<GestureTemplate>
        var onCommit: ([CGPoint], GestureTemplate) -> Void

        init(template: Binding<GestureTemplate>, onCommit: @escaping ([CGPoint], GestureTemplate) -> Void) {
            self.template = template
            self.onCommit = onCommit
        }

        func commit(points: [CGPoint]) {
            let newTemplate = GestureTemplate(points: points)
            template.wrappedValue = newTemplate
            onCommit(points, newTemplate)
        }
    }
}

final class GestureTemplateCanvasNSView: NSView {
    var template = GestureTemplate(signature: GestureSignature([.right])) {
        didSet {
            needsDisplay = true
        }
    }

    var onCommit: ([CGPoint]) -> Void = { _ in }
    private var activePoints: [CGPoint] = []

    override var isFlipped: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        begin(event)
    }

    override func mouseDragged(with event: NSEvent) {
        append(event)
    }

    override func mouseUp(with event: NSEvent) {
        end(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        begin(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        append(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        end(event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        background.fill()
        NSColor.separatorColor.setStroke()
        background.lineWidth = 1
        background.stroke()

        drawReferenceLines()

        let points = activePoints.count > 1 ? activePoints : scaledTemplatePoints()
        drawPath(points, color: .systemBlue, width: activePoints.isEmpty ? 3 : 4)
    }

    private func begin(_ event: NSEvent) {
        activePoints = [convert(event.locationInWindow, from: nil)]
        needsDisplay = true
    }

    private func append(_ event: NSEvent) {
        activePoints.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    private func end(_ event: NSEvent) {
        activePoints.append(convert(event.locationInWindow, from: nil))
        let finished = activePoints
        activePoints = []

        if finished.count > 1 {
            onCommit(finished)
        }
        needsDisplay = true
    }

    private func drawReferenceLines() {
        let path = NSBezierPath()
        path.lineWidth = 1
        let inset = bounds.insetBy(dx: 12, dy: 12)
        path.move(to: CGPoint(x: inset.midX, y: inset.minY))
        path.line(to: CGPoint(x: inset.midX, y: inset.maxY))
        path.move(to: CGPoint(x: inset.minX, y: inset.midY))
        path.line(to: CGPoint(x: inset.maxX, y: inset.midY))
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        path.stroke()
    }

    private func drawPath(_ points: [CGPoint], color: NSColor, width: CGFloat) {
        guard points.count > 1 else {
            return
        }

        color.withAlphaComponent(0.95).setStroke()
        color.setFill()

        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.stroke()

        let start = points[0]
        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: CGRect(x: start.x - 4, y: start.y - 4, width: 8, height: 8)).fill()

        if let end = points.last {
            NSColor.systemBlue.setFill()
            NSBezierPath(ovalIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)).fill()
        }
    }

    private func scaledTemplatePoints() -> [CGPoint] {
        let points = template.cgPoints
        guard points.count > 1 else {
            return []
        }

        let inset = bounds.insetBy(dx: 28, dy: 24)
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let width = max(maxX - minX, 0.01)
        let height = max(maxY - minY, 0.01)
        let scale = min(inset.width / width, inset.height / height)

        let scaledWidth = width * scale
        let scaledHeight = height * scale
        let origin = CGPoint(
            x: inset.midX - scaledWidth / 2,
            y: inset.midY - scaledHeight / 2
        )

        return points.map { point in
            CGPoint(
                x: origin.x + (point.x - minX) * scale,
                y: origin.y + (point.y - minY) * scale
            )
        }
    }
}
