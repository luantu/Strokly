import CoreGraphics
import Foundation

public struct DisplayEdgeBounds: Equatable {
    public var bounds: CGRect

    public init(bounds: CGRect) {
        self.bounds = bounds
    }
}

public enum EdgeScrollDetector {
    public static func activeDisplays() -> [DisplayEdgeBounds] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return [DisplayEdgeBounds(bounds: CGDisplayBounds(CGMainDisplayID()))]
        }

        var displays = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return [DisplayEdgeBounds(bounds: CGDisplayBounds(CGMainDisplayID()))]
        }

        return displays.prefix(Int(displayCount)).map { displayID in
            DisplayEdgeBounds(bounds: CGDisplayBounds(displayID))
        }
    }

    public static func edge(
        for point: CGPoint,
        displays: [DisplayEdgeBounds],
        threshold: CGFloat
    ) -> ScreenEdge? {
        guard let display = displays.first(where: { $0.bounds.contains(point) }) else {
            return nil
        }

        let bounds = display.bounds
        if point.y - bounds.minY <= threshold {
            return .top
        }
        if bounds.maxY - point.y <= threshold {
            return .bottom
        }
        if point.x - bounds.minX <= threshold {
            return .left
        }
        if bounds.maxX - point.x <= threshold {
            return .right
        }
        return nil
    }
}
