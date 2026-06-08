import Foundation

public enum SystemAction: String, CaseIterable, Codable, Hashable, Identifiable {
    case maximizeWindow
    case centerWindow
    case fullscreen
    case minimizeWindow
    case volumeUp
    case volumeDown
    case volumeMute
    case brightnessUp
    case brightnessDown
    case showDesktop
    case missionControl
    case appExpose
    case spotlight
    case forceQuit
    case lockScreen
    case sleepDisplay

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .maximizeWindow: return L10n.string("Maximize Window")
        case .centerWindow: return L10n.string("Center Window")
        case .fullscreen: return L10n.string("Toggle Fullscreen")
        case .minimizeWindow: return L10n.string("Minimize Window")
        case .volumeUp: return L10n.string("Volume Up")
        case .volumeDown: return L10n.string("Volume Down")
        case .volumeMute: return L10n.string("Mute")
        case .brightnessUp: return L10n.string("Brightness Up")
        case .brightnessDown: return L10n.string("Brightness Down")
        case .showDesktop: return L10n.string("Show Desktop")
        case .missionControl: return L10n.string("Mission Control")
        case .appExpose: return L10n.string("App Exposé")
        case .spotlight: return L10n.string("Spotlight")
        case .forceQuit: return L10n.string("Force Quit")
        case .lockScreen: return L10n.string("Lock Screen")
        case .sleepDisplay: return L10n.string("Sleep Display")
        }
    }

    public var icon: String {
        switch self {
        case .maximizeWindow: return "rectangle.expand.vertical"
        case .centerWindow: return "rectangle.center.inset.filled"
        case .fullscreen: return "arrow.up.left.and.arrow.down.right"
        case .minimizeWindow: return "rectangle.compress.vertical"
        case .volumeUp: return "speaker.wave.2.fill"
        case .volumeDown: return "speaker.wave.1.fill"
        case .volumeMute: return "speaker.slash.fill"
        case .brightnessUp: return "sun.max.fill"
        case .brightnessDown: return "sun.min.fill"
        case .showDesktop: return "desktopcomputer"
        case .missionControl: return "square.grid.3x3.fill"
        case .appExpose: return "rectangle.grid.3x2.fill"
        case .spotlight: return "magnifyingglass"
        case .forceQuit: return "xmark.octagon.fill"
        case .lockScreen: return "lock.fill"
        case .sleepDisplay: return "moon.zzz.fill"
        }
    }
}

public struct GestureAction: Codable, Hashable, Equatable {
    public enum Kind: String, CaseIterable, Codable, Identifiable {
        case keyStroke
        case openURL
        case openApplication
        case shellScript
        case appleScript
        case systemAction

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .keyStroke: return L10n.string("Keyboard Shortcut")
            case .openURL: return L10n.string("Open URL")
            case .openApplication: return L10n.string("Open Application")
            case .shellScript: return L10n.string("Run Shell Script")
            case .appleScript: return L10n.string("Run AppleScript")
            case .systemAction: return L10n.string("System Action")
            }
        }

        public var icon: String {
            switch self {
            case .keyStroke: return "keyboard"
            case .openURL: return "link"
            case .openApplication: return "app.badge"
            case .shellScript: return "terminal"
            case .appleScript: return "applescript"
            case .systemAction: return "gearshape.2"
            }
        }
    }

    public var kind: Kind
    public var keyShortcut: KeyboardShortcutSpec?
    public var value: String
    public var systemAction: SystemAction?
    public var focusVisibleWindowBeforeExecution: Bool
    public var runAsAdmin: Bool

    public init(
        kind: Kind,
        keyShortcut: KeyboardShortcutSpec? = nil,
        value: String = "",
        systemAction: SystemAction? = nil,
        focusVisibleWindowBeforeExecution: Bool = false,
        runAsAdmin: Bool = false
    ) {
        self.kind = kind
        self.keyShortcut = keyShortcut
        self.value = value
        self.systemAction = systemAction
        self.focusVisibleWindowBeforeExecution = focusVisibleWindowBeforeExecution
        self.runAsAdmin = runAsAdmin
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case keyShortcut
        case value
        case systemAction
        case focusVisibleWindowBeforeExecution
        case runAsAdmin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        keyShortcut = try container.decodeIfPresent(KeyboardShortcutSpec.self, forKey: .keyShortcut)
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        systemAction = try container.decodeIfPresent(SystemAction.self, forKey: .systemAction)
        focusVisibleWindowBeforeExecution = try container.decodeIfPresent(Bool.self, forKey: .focusVisibleWindowBeforeExecution) ?? false
        runAsAdmin = try container.decodeIfPresent(Bool.self, forKey: .runAsAdmin) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(keyShortcut, forKey: .keyShortcut)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(systemAction, forKey: .systemAction)
        try container.encode(focusVisibleWindowBeforeExecution, forKey: .focusVisibleWindowBeforeExecution)
        try container.encodeIfPresent(runAsAdmin, forKey: .runAsAdmin)
    }

    public static func keyStroke(_ shortcut: KeyboardShortcutSpec) -> GestureAction {
        GestureAction(kind: .keyStroke, keyShortcut: shortcut)
    }

    public static func openURL(_ url: String) -> GestureAction {
        GestureAction(kind: .openURL, value: url)
    }

    public static func openApplication(_ path: String) -> GestureAction {
        GestureAction(kind: .openApplication, value: path)
    }

    public static func shellScript(_ script: String) -> GestureAction {
        GestureAction(kind: .shellScript, value: script)
    }

    public static func appleScript(_ script: String) -> GestureAction {
        GestureAction(kind: .appleScript, value: script)
    }

    public static func systemAction(_ action: SystemAction) -> GestureAction {
        GestureAction(kind: .systemAction, systemAction: action)
    }

    public var displaySummary: String {
        switch kind {
        case .keyStroke:
            return keyShortcut?.displayText ?? L10n.string("Unassigned shortcut")
        case .openURL, .openApplication:
            return value.isEmpty ? L10n.string("Unassigned target") : value
        case .shellScript:
            return value.isEmpty ? L10n.string("No shell script") : L10n.string("Shell script")
        case .appleScript:
            return value.isEmpty ? L10n.string("No AppleScript") : L10n.string("AppleScript")
        case .systemAction:
            return systemAction?.displayName ?? L10n.string("No system action")
        }
    }
}
