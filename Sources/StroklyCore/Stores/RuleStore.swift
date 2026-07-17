import Combine
import Foundation

@MainActor
public final class RuleStore: ObservableObject {
    @Published public var rules: [GestureRule] {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

    private let storageURL: URL
    private var isLoading = false

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        self.rules = GestureRule.defaultRules
        load()
    }

    public func addRule() {
        rules.append(
            GestureRule(
                name: "New Gesture",
                signature: GestureSignature([.down, .right]),
                scope: .global,
                action: .keyStroke(KeyboardShortcutSpec(key: "space", modifiers: [.command]))
            )
        )
    }

    public func deleteRule(id: GestureRule.ID) {
        rules.removeAll { $0.id == id }
    }

    public func resetDefaults() {
        rules = GestureRule.defaultRules
    }

    public func reload() {
        load()
    }

    public func importFromFile(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        let imported = try JSONDecoder.stroklyDecoder.decode([GestureRule].self, from: data)
        rules.append(contentsOf: imported)
    }

    public func exportToFile(_ url: URL) throws {
        let data = try JSONEncoder.stroklyEncoder.encode(rules)
        try data.write(to: url, options: [.atomic])
    }

    public func save() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.stroklyEncoder.encode(rules)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save rules: \(error)")
        }
    }

    private func load() {
        isLoading = true
        defer {
            isLoading = false
        }

        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            rules = GestureRule.defaultRules
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            rules = try JSONDecoder.stroklyDecoder.decode([GestureRule].self, from: data)
            migrateMissingEdgeScrollRulesIfNeeded()
            migrateOldToleranceIfNeeded()
        } catch {
            rules = GestureRule.defaultRules
        }
    }

    private func migrateMissingEdgeScrollRulesIfNeeded() {
        guard !rules.contains(where: { $0.triggerButton == .edgeScroll }) else {
            return
        }

        let edgeRules = GestureRule.defaultRules.filter { $0.triggerButton == .edgeScroll }
        guard !edgeRules.isEmpty else { return }
        rules.append(contentsOf: edgeRules)
        StroklyLogger.shared.info("rules.migrate.edgeScrollDefaults", ["count": "\(edgeRules.count)"])
        save()
    }

    private func migrateOldToleranceIfNeeded() {
        // The (x,y) DTW algorithm uses a different distance scale.
        // Values > 0.3 are from the old turning-angle or $1 scale and need migration.
        let needsSave = rules.contains { $0.matchTolerance > 0.3 || $0.matchTolerance < 0.02 }
        if needsSave {
            StroklyLogger.shared.info("rules.migrate.tolerance", [
                "count": "\(rules.filter { $0.matchTolerance > 0.3 || $0.matchTolerance < 0.02 }.count)"
            ])
            save()
        }
    }

    private static func defaultStorageURL() -> URL {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return supportDirectory
            .appendingPathComponent("Strokly", isDirectory: true)
            .appendingPathComponent("Rules.json")
    }
}

private extension JSONEncoder {
    static var stroklyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var stroklyDecoder: JSONDecoder {
        JSONDecoder()
    }
}
