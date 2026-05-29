import CoreGraphics
import Foundation

public struct GestureCandidate: Equatable {
    public var signature: GestureSignature
    public var template: GestureTemplate
    public var points: [CGPoint]
}

public struct GestureRecognizer {
    public var minSegmentLength: CGFloat
    public var minPathLength: CGFloat

    public init(minSegmentLength: CGFloat = 24, minPathLength: CGFloat = 24) {
        self.minSegmentLength = minSegmentLength
        self.minPathLength = minPathLength
    }

    public func analyze(_ points: [CGPoint]) -> GestureCandidate? {
        guard pathLength(points) >= minPathLength,
              let signature = recognize(points) else {
            return nil
        }

        return GestureCandidate(
            signature: signature,
            template: GestureTemplate(points: points),
            points: points
        )
    }

    public func recognize(_ points: [CGPoint]) -> GestureSignature? {
        guard points.count > 1 else {
            return nil
        }

        var anchor = points[0]
        var directions: [GestureDirection] = []
        var lastDirection: GestureDirection?

        for point in points.dropFirst() {
            let dx = point.x - anchor.x
            let dy = point.y - anchor.y
            guard hypot(dx, dy) >= minSegmentLength else {
                continue
            }

            let direction = GestureDirection.dominantDirection(dx: dx, dy: dy)
            if direction != lastDirection {
                directions.append(direction)
                lastDirection = direction
            }
            anchor = point
        }

        guard !directions.isEmpty else {
            return nil
        }

        return GestureSignature(directions)
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else {
            return 0
        }

        return zip(points, points.dropFirst()).reduce(CGFloat(0)) { partial, pair in
            partial + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }
}
