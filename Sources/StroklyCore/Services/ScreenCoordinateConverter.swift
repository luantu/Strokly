import AppKit
import CoreGraphics
import Foundation

struct ScreenCoordinateConverter {
    struct DisplayMapping {
        var displayID: CGDirectDisplayID
        var cgBounds: CGRect
        var appKitFrame: CGRect

        func containsCGPoint(_ point: CGPoint) -> Bool {
            cgBounds.contains(point)
        }

        func appKitPoint(fromCGPoint point: CGPoint) -> CGPoint {
            let localX = point.x - cgBounds.minX
            let localY = point.y - cgBounds.minY
            return CGPoint(
                x: appKitFrame.minX + localX,
                y: appKitFrame.maxY - localY
            )
        }
    }

    var mappings: [DisplayMapping]

    init(screens: [NSScreen] = NSScreen.screens) {
        self.mappings = screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)

            return DisplayMapping(
                displayID: displayID,
                cgBounds: CGDisplayBounds(displayID),
                appKitFrame: screen.frame
            )
        }
    }

    var appKitDesktopFrame: CGRect {
        mappings.reduce(CGRect.null) { result, mapping in
            result.isNull ? mapping.appKitFrame : result.union(mapping.appKitFrame)
        }
    }

    func displayMapping(for point: CGPoint) -> DisplayMapping? {
        mappings.first { $0.containsCGPoint(point) } ?? mappings.first
    }

    func appKitPoint(fromCGPoint point: CGPoint) -> CGPoint {
        guard let mapping = displayMapping(for: point) else {
            return point
        }
        return mapping.appKitPoint(fromCGPoint: point)
    }
}
