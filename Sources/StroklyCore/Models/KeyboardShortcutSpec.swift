import CoreGraphics
import Foundation

public enum KeyboardModifier: String, CaseIterable, Codable, Hashable, Identifiable {
    case control
    case option
    case shift
    case command

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .control:
            return "Control"
        case .option:
            return "Option"
        case .shift:
            return "Shift"
        case .command:
            return "Command"
        }
    }

    public var symbol: String {
        switch self {
        case .control:
            return "⌃"
        case .option:
            return "⌥"
        case .shift:
            return "⇧"
        case .command:
            return "⌘"
        }
    }

    var sortOrder: Int {
        switch self {
        case .control:
            return 0
        case .option:
            return 1
        case .shift:
            return 2
        case .command:
            return 3
        }
    }

    var eventFlag: CGEventFlags {
        switch self {
        case .control:
            return .maskControl
        case .option:
            return .maskAlternate
        case .shift:
            return .maskShift
        case .command:
            return .maskCommand
        }
    }
}

public struct KeyboardShortcutSpec: Codable, Hashable, Equatable {
    public var key: String
    public var modifiers: [KeyboardModifier]

    public init(key: String, modifiers: [KeyboardModifier]) {
        self.key = key
        self.modifiers = Array(Set(modifiers)).sorted { $0.sortOrder < $1.sortOrder }
    }

    public var keyCode: CGKeyCode? {
        KeyCodeResolver.keyCode(for: key)
    }

    public var displayText: String {
        let prefix = modifiers
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.symbol)
            .joined()
        return prefix + KeyCodeResolver.displayKey(for: key)
    }

    var flags: CGEventFlags {
        modifiers.reduce(CGEventFlags()) { result, modifier in
            result.union(modifier.eventFlag)
        }
    }
}

enum KeyCodeResolver {
    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
        "`": 50, "delete": 51, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "leftarrow": 123, "rightarrow": 124, "downarrow": 125, "uparrow": 126,
        "pageup": 116, "pagedown": 121, "home": 115, "end": 119
    ]

    static let displayMap: [String: String] = [
        "space": "Space", "leftarrow": "←", "rightarrow": "→",
        "uparrow": "↑", "downarrow": "↓", "escape": "Esc",
        "return": "Return", "tab": "Tab", "delete": "⌫",
        "pageup": "Page↑", "pagedown": "Page↓", "home": "Home",
        "end": "End",
        "f1": "F1", "f2": "F2", "f3": "F3", "f4": "F4",
        "f5": "F5", "f6": "F6", "f7": "F7", "f8": "F8",
        "f9": "F9", "f10": "F10", "f11": "F11", "f12": "F12"
    ]

    static func keyCode(for key: String) -> CGKeyCode? {
        keyCodes[normalize(key)]
    }

    static func displayKey(for key: String) -> String {
        let n = normalize(key)
        return displayMap[n] ?? key.uppercased()
    }

    static func normalize(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    static func keyCodeToDisplay(_ code: CGKeyCode) -> String? {
        for (k, v) in keyCodes where v == code {
            return displayKey(for: k)
        }
        return nil
    }

    static func keyCodeToName(_ code: CGKeyCode) -> String? {
        for (k, v) in keyCodes where v == code {
            return k
        }
        return nil
    }

    static func isKnownKey(_ key: String) -> Bool {
        keyCodes[normalize(key)] != nil
    }
}
