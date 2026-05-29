import Foundation

public enum ScreenEdge: String, CaseIterable, Codable, Hashable, Identifiable {
    case top
    case bottom
    case left
    case right

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .top: return L10n.string("Top")
        case .bottom: return L10n.string("Bottom")
        case .left: return L10n.string("Left")
        case .right: return L10n.string("Right")
        }
    }

    public var arrowSymbol: String {
        switch self {
        case .top: return "↑"
        case .bottom: return "↓"
        case .left: return "←"
        case .right: return "→"
        }
    }
}

public enum ScrollDirection: String, CaseIterable, Codable, Hashable, Identifiable {
    case up
    case down

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .up: return L10n.string("Scroll Up")
        case .down: return L10n.string("Scroll Down")
        }
    }
}

public struct EdgeScrollRule: Codable, Identifiable, Hashable, Equatable {
    public var id: UUID
    public var name: String
    public var edge: ScreenEdge
    public var direction: ScrollDirection
    public var action: GestureAction
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        edge: ScreenEdge,
        direction: ScrollDirection,
        action: GestureAction,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.edge = edge
        self.direction = direction
        self.action = action
        self.isEnabled = isEnabled
    }

    public var displayText: String {
        "\(edge.arrowSymbol) \(direction.displayName)"
    }

    public static let defaultRules: [EdgeScrollRule] = [
        EdgeScrollRule(name: "Volume Up", edge: .top, direction: .up, action: .systemAction(.volumeUp)),
        EdgeScrollRule(name: "Volume Down", edge: .top, direction: .down, action: .systemAction(.volumeDown)),
        EdgeScrollRule(name: "Brightness Up", edge: .bottom, direction: .up, action: .systemAction(.brightnessUp)),
        EdgeScrollRule(name: "Brightness Down", edge: .bottom, direction: .down, action: .systemAction(.brightnessDown)),
        EdgeScrollRule(name: "Mission Control", edge: .left, direction: .up, action: .keyStroke(.init(key: "upArrow", modifiers: [.control]))),
        EdgeScrollRule(name: "App Exposé", edge: .left, direction: .down, action: .keyStroke(.init(key: "downArrow", modifiers: [.control]))),
        EdgeScrollRule(name: "Next Desktop", edge: .right, direction: .up, action: .keyStroke(.init(key: "rightArrow", modifiers: [.control]))),
        EdgeScrollRule(name: "Previous Desktop", edge: .right, direction: .down, action: .keyStroke(.init(key: "leftArrow", modifiers: [.control])))
    ]
}
