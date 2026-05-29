import CoreGraphics
import Foundation

public struct GesturePoint: Codable, Hashable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public struct GestureTemplate: Codable, Hashable, Equatable {
    public static let sampleCount = 32

    public var points: [GesturePoint]

    public init(points: [CGPoint]) {
        self.points = GestureTemplateNormalizer.normalized(points, sampleCount: Self.sampleCount)
            .map(GesturePoint.init)
    }

    public init(signature: GestureSignature) {
        self.init(points: GestureTemplate.canonicalPoints(for: signature))
    }

    public var cgPoints: [CGPoint] {
        points.map(\.cgPoint)
    }

    public var isEmpty: Bool {
        points.isEmpty
    }

    private static func canonicalPoints(for signature: GestureSignature) -> [CGPoint] {
        let diagonal: CGFloat = 70.71
        var points = [CGPoint(x: 0, y: 0)]
        var current = points[0]

        for direction in signature.directions {
            switch direction {
            case .up: current.y -= 100
            case .down: current.y += 100
            case .left: current.x -= 100
            case .right: current.x += 100
            case .upLeft: current.x -= diagonal; current.y -= diagonal
            case .upRight: current.x += diagonal; current.y -= diagonal
            case .downLeft: current.x -= diagonal; current.y += diagonal
            case .downRight: current.x += diagonal; current.y += diagonal
            }
            points.append(current)
        }

        return points
    }
}

public enum GestureTemplateNormalizer {
    public static func normalized(_ points: [CGPoint], sampleCount: Int) -> [CGPoint] {
        let cleaned = removeNearDuplicates(points)
        guard cleaned.count > 1, sampleCount > 1 else {
            return []
        }

        let resampled = resample(cleaned, sampleCount: sampleCount)
        guard !resampled.isEmpty else {
            return []
        }

        let minX = resampled.map(\.x).min() ?? 0
        let maxX = resampled.map(\.x).max() ?? 0
        let minY = resampled.map(\.y).min() ?? 0
        let maxY = resampled.map(\.y).max() ?? 0
        let scale = max(maxX - minX, maxY - minY)
        guard scale > 0 else {
            return []
        }

        let centered = resampled.map { point in
            CGPoint(
                x: (point.x - minX) / scale,
                y: (point.y - minY) / scale
            )
        }

        let centerX = centered.map(\.x).reduce(CGFloat(0), +) / CGFloat(centered.count)
        let centerY = centered.map(\.y).reduce(CGFloat(0), +) / CGFloat(centered.count)

        return centered.map { point in
            CGPoint(x: point.x - centerX, y: point.y - centerY)
        }
    }

    private static func removeNearDuplicates(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if let last = result.last, hypot(point.x - last.x, point.y - last.y) < 1 {
                continue
            }
            result.append(point)
        }
        return result
    }

    private static func resample(_ points: [CGPoint], sampleCount: Int) -> [CGPoint] {
        let totalLength = pathLength(points)
        guard totalLength > 0 else {
            return []
        }

        let interval = totalLength / CGFloat(sampleCount - 1)
        var result = [points[0]]
        var distanceSinceLastSample: CGFloat = 0
        var previous = points[0]
        var index = 1

        while index < points.count {
            let current = points[index]
            let segmentLength = hypot(current.x - previous.x, current.y - previous.y)

            if distanceSinceLastSample + segmentLength >= interval {
                let remaining = interval - distanceSinceLastSample
                let ratio = segmentLength == 0 ? 0 : remaining / segmentLength
                let sample = CGPoint(
                    x: previous.x + ratio * (current.x - previous.x),
                    y: previous.y + ratio * (current.y - previous.y)
                )
                result.append(sample)
                previous = sample
                distanceSinceLastSample = 0
            } else {
                distanceSinceLastSample += segmentLength
                previous = current
                index += 1
            }
        }

        while result.count < sampleCount {
            result.append(points[points.count - 1])
        }

        if result.count > sampleCount {
            result = Array(result.prefix(sampleCount))
        }

        return result
    }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else {
            return 0
        }

        return zip(points, points.dropFirst()).reduce(CGFloat(0)) { partial, pair in
            partial + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }
}

public enum GestureTemplateMatcher {
    public static func distance(_ first: GestureTemplate, _ second: GestureTemplate) -> Double {
        let left = first.cgPoints
        let right = second.cgPoints
        guard left.count == right.count, !left.isEmpty else {
            return .greatestFiniteMagnitude
        }

        let total = zip(left, right).reduce(Double(0)) { partial, pair in
            partial + Double(hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y))
        }
        return total / Double(left.count)
    }
}
