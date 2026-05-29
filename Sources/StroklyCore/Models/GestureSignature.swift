import Foundation

public struct GestureSignature: Codable, Hashable, Equatable, ExpressibleByArrayLiteral {
    public var directions: [GestureDirection]

    public init(_ directions: [GestureDirection]) {
        self.directions = directions
    }

    public init(arrayLiteral elements: GestureDirection...) {
        self.directions = elements
    }

    public init(compactText: String) throws {
        let trimmed = compactText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GestureSignatureError.empty
        }

        let separatorCharacters = CharacterSet(charactersIn: ",; /-")
        let components = trimmed.components(separatedBy: separatorCharacters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let tokens: [String]
        if components.count > 1 {
            tokens = components
        } else if GestureDirection.parse(trimmed) != nil {
            tokens = [trimmed]
        } else {
            tokens = trimmed.map(String.init)
        }

        let parsed = tokens.compactMap(GestureDirection.parse)
        guard parsed.count == tokens.count, !parsed.isEmpty else {
            throw GestureSignatureError.invalidToken(compactText)
        }

        self.directions = parsed
    }

    public var compactText: String {
        directions.map(\.rawValue).joined()
    }

    public var displayText: String {
        directions.map(\.displayName).joined(separator: " ")
    }

    public var arrowText: String {
        directions.map(\.arrowSymbol).joined(separator: " ")
    }
}

public enum GestureSignatureError: Error, LocalizedError, Equatable {
    case empty
    case invalidToken(String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Gesture cannot be empty."
        case .invalidToken(let token):
            return "Unsupported gesture token: \(token)"
        }
    }
}
