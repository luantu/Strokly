import Foundation

public enum TriggerButton: String, CaseIterable, Codable, Hashable, Identifiable {
    case rightMouse
    case middleMouse
    case button4
    case button5
    case edgeScroll

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rightMouse: return L10n.string("Right Mouse")
        case .middleMouse: return L10n.string("Middle Mouse")
        case .button4: return L10n.string("Button 4")
        case .button5: return L10n.string("Button 5")
        case .edgeScroll: return L10n.string("Edge Scroll")
        }
    }

    public var icon: String {
        switch self {
        case .rightMouse: return "computermouse"
        case .middleMouse: return "computermouse.fill"
        case .button4: return "mouse"
        case .button5: return "mouse.fill"
        case .edgeScroll: return "rectangle.dashed"
        }
    }
}

public struct RuleScope: Codable, Hashable, Equatable {
    public enum Kind: String, CaseIterable, Codable, Identifiable {
        case global
        case application

        public var id: String { rawValue }
    }

    public var kind: Kind
    public var bundleIdentifier: String

    public static var global: RuleScope {
        RuleScope(kind: .global, bundleIdentifier: "")
    }

    public static func application(bundleIdentifier: String) -> RuleScope {
        RuleScope(kind: .application, bundleIdentifier: bundleIdentifier)
    }

    public var displayText: String {
        switch kind {
        case .global:
            return L10n.string("All Apps")
        case .application:
            return bundleIdentifier.isEmpty ? L10n.string("Specific App") : bundleIdentifier
        }
    }
}

public struct GestureRule: Codable, Identifiable, Hashable, Equatable {
    public var id: UUID
    public var name: String
    public var category: String
    public var signature: GestureSignature
    public var template: GestureTemplate
    public var triggerButton: TriggerButton
    public var edge: ScreenEdge?
    public var scrollDirection: ScrollDirection?
    public var modifierRequirements: [KeyboardModifier]
    public var scope: RuleScope
    public var action: GestureAction
    public var isEnabled: Bool
    public var showTip: Bool
    public var matchTolerance: Double

    public init(
        id: UUID = UUID(),
        name: String,
        category: String = "Custom",
        signature: GestureSignature,
        template: GestureTemplate? = nil,
        triggerButton: TriggerButton = .rightMouse,
        edge: ScreenEdge? = nil,
        scrollDirection: ScrollDirection? = nil,
        modifierRequirements: [KeyboardModifier] = [],
        scope: RuleScope,
        action: GestureAction,
        isEnabled: Bool = true,
        showTip: Bool = true,
        matchTolerance: Double = 0.15
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.signature = signature
        self.template = template ?? GestureTemplate(signature: signature)
        self.triggerButton = triggerButton
        self.edge = edge
        self.scrollDirection = scrollDirection
        self.modifierRequirements = modifierRequirements
        self.scope = scope
        self.action = action
        self.isEnabled = isEnabled
        self.showTip = showTip
        self.matchTolerance = matchTolerance
    }

    public init(
        id: UUID = UUID(),
        name: String,
        category: String = "Custom",
        template: GestureTemplate,
        triggerButton: TriggerButton = .rightMouse,
        edge: ScreenEdge? = nil,
        scrollDirection: ScrollDirection? = nil,
        modifierRequirements: [KeyboardModifier] = [],
        scope: RuleScope,
        action: GestureAction,
        isEnabled: Bool = true,
        showTip: Bool = true,
        matchTolerance: Double = 0.15
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.template = template
        self.signature = GestureSignature([])
        self.triggerButton = triggerButton
        self.edge = edge
        self.scrollDirection = scrollDirection
        self.modifierRequirements = modifierRequirements
        self.scope = scope
        self.action = action
        self.isEnabled = isEnabled
        self.showTip = showTip
        self.matchTolerance = matchTolerance
    }

    enum CodingKeys: String, CodingKey {
        case id, name, category, signature, template, triggerButton
        case edge, scrollDirection, modifierRequirements, scope, action, isEnabled, showTip, matchTolerance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "Custom"
        signature = try c.decodeIfPresent(GestureSignature.self, forKey: .signature) ?? GestureSignature([])
        template = try c.decodeIfPresent(GestureTemplate.self, forKey: .template) ?? GestureTemplate(signature: signature)
        triggerButton = try c.decodeIfPresent(TriggerButton.self, forKey: .triggerButton) ?? .rightMouse
        edge = try c.decodeIfPresent(ScreenEdge.self, forKey: .edge)
        scrollDirection = try c.decodeIfPresent(ScrollDirection.self, forKey: .scrollDirection)
        modifierRequirements = try c.decodeIfPresent([KeyboardModifier].self, forKey: .modifierRequirements) ?? []
        scope = try c.decode(RuleScope.self, forKey: .scope)
        action = try c.decode(GestureAction.self, forKey: .action)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        showTip = try c.decodeIfPresent(Bool.self, forKey: .showTip) ?? true
        matchTolerance = try c.decodeIfPresent(Double.self, forKey: .matchTolerance) ?? 0.15
        // Migrate from turning-angle scale (0.28–1.47) to (x,y) coordinate scale
        if matchTolerance > 0.3 {
            matchTolerance *= 0.15
        }
        // Migrate from original $1 recognizer scale (0.08–0.42)
        if matchTolerance < 0.02 {
            matchTolerance = max(matchTolerance, 0.05)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category)
        try c.encode(signature, forKey: .signature)
        try c.encode(template, forKey: .template)
        try c.encode(triggerButton, forKey: .triggerButton)
        try c.encodeIfPresent(edge, forKey: .edge)
        try c.encodeIfPresent(scrollDirection, forKey: .scrollDirection)
        try c.encode(modifierRequirements, forKey: .modifierRequirements)
        try c.encode(scope, forKey: .scope)
        try c.encode(action, forKey: .action)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(showTip, forKey: .showTip)
        try c.encode(matchTolerance, forKey: .matchTolerance)
    }

    public var displayTrigger: String {
        switch triggerButton {
        case .edgeScroll:
            let e = edge?.displayName ?? "?"
            let d = scrollDirection?.displayName ?? "?"
            return "Edge: \(e) \(d)"
        default:
            return triggerButton.displayName
        }
    }
}

public extension GestureRule {
    var gestureDisplayText: String {
        signature.directions.isEmpty ? "Custom shape" : signature.arrowText
    }

    static let defaultRules: [GestureRule] = [
        GestureRule(name: "Back", category: "Navigation", signature: GestureSignature([.left]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "[", modifiers: [.command]))),
        GestureRule(name: "Forward", category: "Navigation", signature: GestureSignature([.right]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "]", modifiers: [.command]))),
        GestureRule(name: "Mission Control", category: "Navigation", signature: GestureSignature([.up]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "upArrow", modifiers: [.control]))),
        GestureRule(name: "Close Tab or Window", category: "Tabs", signature: GestureSignature([.down]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "w", modifiers: [.command]))),
        GestureRule(name: "New Tab", category: "Tabs", signature: GestureSignature([.up, .right]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "t", modifiers: [.command]))),
        GestureRule(name: "Volume Up", category: "Edge Scroll", signature: GestureSignature([]), triggerButton: .edgeScroll, edge: .top, scrollDirection: .up, scope: .global, action: .systemAction(.volumeUp)),
        GestureRule(name: "Volume Down", category: "Edge Scroll", signature: GestureSignature([]), triggerButton: .edgeScroll, edge: .top, scrollDirection: .down, scope: .global, action: .systemAction(.volumeDown)),
        GestureRule(name: "Brightness Up", category: "Edge Scroll", signature: GestureSignature([]), triggerButton: .edgeScroll, edge: .bottom, scrollDirection: .up, scope: .global, action: .systemAction(.brightnessUp)),
        GestureRule(name: "Brightness Down", category: "Edge Scroll", signature: GestureSignature([]), triggerButton: .edgeScroll, edge: .bottom, scrollDirection: .down, scope: .global, action: .systemAction(.brightnessDown)),
        GestureRule(name: "Mission Control", category: "Edge Scroll", signature: GestureSignature([]), triggerButton: .edgeScroll, edge: .left, scrollDirection: .up, scope: .global, action: .systemAction(.missionControl)),
        GestureRule(name: "App Exposé", category: "Edge Scroll", signature: GestureSignature([]), triggerButton: .edgeScroll, edge: .left, scrollDirection: .down, scope: .global, action: .systemAction(.appExpose)),
        GestureRule(name: "Next Desktop", category: "Edge Scroll", signature: GestureSignature([]), triggerButton: .edgeScroll, edge: .right, scrollDirection: .up, scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "rightArrow", modifiers: [.control]))),
        GestureRule(name: "Previous Desktop", category: "Edge Scroll", signature: GestureSignature([]), triggerButton: .edgeScroll, edge: .right, scrollDirection: .down, scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "leftArrow", modifiers: [.control])))
    ]

    static let libraryPresets: [GestureRule] = [
        GestureRule(name: "Back", category: "Navigation", signature: GestureSignature([.left]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "[", modifiers: [.command]))),
        GestureRule(name: "Forward", category: "Navigation", signature: GestureSignature([.right]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "]", modifiers: [.command]))),
        GestureRule(name: "Mission Control", category: "Navigation", signature: GestureSignature([.up]), scope: .global, action: .systemAction(.missionControl)),
        GestureRule(name: "App Exposé", category: "Navigation", signature: GestureSignature([.down]), scope: .global, action: .systemAction(.appExpose)),
        GestureRule(name: "Show Desktop", category: "Navigation", signature: GestureSignature([.up, .down]), scope: .global, action: .systemAction(.showDesktop)),
        GestureRule(name: "Copy", category: "Clipboard", signature: GestureSignature([.down, .up]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "c", modifiers: [.command]))),
        GestureRule(name: "Paste", category: "Clipboard", signature: GestureSignature([.up, .down]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "v", modifiers: [.command]))),
        GestureRule(name: "Undo", category: "Clipboard", signature: GestureSignature([.left, .left]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "z", modifiers: [.command]))),
        GestureRule(name: "Redo", category: "Clipboard", signature: GestureSignature([.right, .right]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "z", modifiers: [.command, .shift]))),
        GestureRule(name: "Close Tab or Window", category: "Tabs", signature: GestureSignature([.down]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "w", modifiers: [.command]))),
        GestureRule(name: "New Tab", category: "Tabs", signature: GestureSignature([.up, .right]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "t", modifiers: [.command]))),
        GestureRule(name: "Reopen Closed Tab", category: "Tabs", signature: GestureSignature([.down, .up]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "t", modifiers: [.command, .shift]))),
        GestureRule(name: "Next Tab", category: "Tabs", signature: GestureSignature([.right, .up]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "]", modifiers: [.command, .shift]))),
        GestureRule(name: "Previous Tab", category: "Tabs", signature: GestureSignature([.left, .up]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "[", modifiers: [.command, .shift]))),
        GestureRule(name: "Switch App", category: "Applications", signature: GestureSignature([.downRight]), scope: .global, action: .keyStroke(KeyboardShortcutSpec(key: "tab", modifiers: [.command]))),
        GestureRule(name: "Spotlight", category: "Applications", signature: GestureSignature([.upRight]), scope: .global, action: .systemAction(.spotlight)),
        GestureRule(name: "Force Quit", category: "System", signature: GestureSignature([.up, .right, .down]), scope: .global, action: .systemAction(.forceQuit)),
        GestureRule(name: "Maximize Window", category: "Window", signature: GestureSignature([.up, .up]), scope: .global, action: .systemAction(.maximizeWindow)),
        GestureRule(name: "Center Window", category: "Window", signature: GestureSignature([.down, .down]), scope: .global, action: .systemAction(.centerWindow)),
        GestureRule(name: "Toggle Fullscreen", category: "Window", signature: GestureSignature([.right, .left]), scope: .global, action: .systemAction(.fullscreen)),
        GestureRule(name: "Volume Up", category: "Media", signature: GestureSignature([.upRight, .upRight]), scope: .global, action: .systemAction(.volumeUp)),
        GestureRule(name: "Volume Down", category: "Media", signature: GestureSignature([.downRight, .downRight]), scope: .global, action: .systemAction(.volumeDown)),
        GestureRule(name: "Lock Screen", category: "System", signature: GestureSignature([.left, .right, .left]), scope: .global, action: .systemAction(.lockScreen))
    ]
}
