import Foundation

public enum StroklyLogLevel: String, CaseIterable, Codable, Identifiable, Comparable {
    case off
    case error
    case warning
    case info
    case debug
    case trace

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return L10n.string("Off")
        case .error: return L10n.string("Error")
        case .warning: return L10n.string("Warning")
        case .info: return L10n.string("Info")
        case .debug: return L10n.string("Debug")
        case .trace: return L10n.string("Trace")
        }
    }

    public static func < (lhs: StroklyLogLevel, rhs: StroklyLogLevel) -> Bool {
        lhs.priority < rhs.priority
    }

    private var priority: Int {
        switch self {
        case .off: return 0
        case .error: return 1
        case .warning: return 2
        case .info: return 3
        case .debug: return 4
        case .trace: return 5
        }
    }
}

public final class StroklyLogger {
    public static let shared = StroklyLogger()

    private let queue = DispatchQueue(label: "com.luantu.Strokly.logger", qos: .utility)
    private let formatter: ISO8601DateFormatter
    private var level: StroklyLogLevel = .info
    private var fileLoggingEnabled = true
    private var logFileURL: URL

    private init() {
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        logFileURL = Self.defaultLogFileURL()
    }

    public static func defaultLogFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Strokly", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("strokly.log")
    }

    public var currentLogFileURL: URL {
        queue.sync { logFileURL }
    }

    public func configure(level: StroklyLogLevel, fileLoggingEnabled: Bool) {
        queue.async {
            self.level = level
            self.fileLoggingEnabled = fileLoggingEnabled
            self.writeUnlocked(.info, "logger.configure", [
                "level": level.rawValue,
                "fileLogging": String(fileLoggingEnabled),
                "path": self.logFileURL.path
            ])
        }
    }

    public func log(_ level: StroklyLogLevel, _ message: String, _ fields: [String: String] = [:]) {
        queue.async {
            self.writeUnlocked(level, message, fields)
        }
    }

    public func error(_ message: String, _ fields: [String: String] = [:]) {
        log(.error, message, fields)
    }

    public func warning(_ message: String, _ fields: [String: String] = [:]) {
        log(.warning, message, fields)
    }

    public func info(_ message: String, _ fields: [String: String] = [:]) {
        log(.info, message, fields)
    }

    public func debug(_ message: String, _ fields: [String: String] = [:]) {
        log(.debug, message, fields)
    }

    public func trace(_ message: String, _ fields: [String: String] = [:]) {
        log(.trace, message, fields)
    }

    private func writeUnlocked(_ level: StroklyLogLevel, _ message: String, _ fields: [String: String]) {
        guard self.level != .off, level <= self.level else { return }

        let fieldText = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.replacingOccurrences(of: "\n", with: "\\n"))" }
            .joined(separator: " ")
        let line = "\(formatter.string(from: Date())) [\(level.rawValue.uppercased())] \(message)\(fieldText.isEmpty ? "" : " \(fieldText)")\n"

        #if DEBUG
        fputs(line, stderr)
        #endif

        guard fileLoggingEnabled else { return }
        do {
            try FileManager.default.createDirectory(
                at: logFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logFileURL)
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
            try handle.close()
        } catch {
            fputs("Strokly logger failed: \(error)\n", stderr)
        }
    }
}
