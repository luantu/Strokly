import CoreGraphics
import Foundation

public enum GestureDirection: String, CaseIterable, Codable, Hashable, Identifiable {
    case up = "U"
    case down = "D"
    case left = "L"
    case right = "R"
    case upLeft = "UL"
    case upRight = "UR"
    case downLeft = "DL"
    case downRight = "DR"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .up: return L10n.string("Up")
        case .down: return L10n.string("Down")
        case .left: return L10n.string("Left")
        case .right: return L10n.string("Right")
        case .upLeft: return L10n.string("Up-Left")
        case .upRight: return L10n.string("Up-Right")
        case .downLeft: return L10n.string("Down-Left")
        case .downRight: return L10n.string("Down-Right")
        }
    }

    public var arrowSymbol: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .upLeft: return "↖"
        case .upRight: return "↗"
        case .downLeft: return "↙"
        case .downRight: return "↘"
        }
    }

    public static func parse(_ token: String) -> GestureDirection? {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "u", "up", "north": return .up
        case "d", "down", "south": return .down
        case "l", "left", "west": return .left
        case "r", "right", "east": return .right
        case "ul", "upleft", "northwest", "nw": return .upLeft
        case "ur", "upright", "northeast", "ne": return .upRight
        case "dl", "downleft", "southwest", "sw": return .downLeft
        case "dr", "downright", "southeast", "se": return .downRight
        default: return nil
        }
    }

    static func dominantDirection(dx: CGFloat, dy: CGFloat) -> GestureDirection {
        let absDx = abs(dx)
        let absDy = abs(dy)
        let diagonalRatio: CGFloat = 0.414

        if absDx < 0.001 && absDy < 0.001 {
            return .right
        }

        let ratio = absDy / max(absDx, 0.001)

        if ratio > diagonalRatio && ratio < (1.0 / diagonalRatio) {
            if dx >= 0 && dy >= 0 { return .downRight }
            if dx >= 0 && dy < 0 { return .upRight }
            if dx < 0 && dy >= 0 { return .downLeft }
            return .upLeft
        }

        if absDx >= absDy {
            return dx >= 0 ? .right : .left
        }

        return dy >= 0 ? .down : .up
    }
}
