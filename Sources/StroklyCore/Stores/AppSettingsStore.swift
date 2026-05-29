import AppKit
import Combine
import Foundation
import ServiceManagement

public enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case en
    case zhHans

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return L10n.string("Follow System")
        case .en: return "English"
        case .zhHans: return "简体中文"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .en: return "en"
        case .zhHans: return "zh-Hans"
        }
    }

    var effectiveLocaleIdentifier: String {
        localeIdentifier ?? Locale.current.identifier
    }
}

@MainActor
public final class AppSettingsStore: ObservableObject {
    @Published public var launchAtLogin: Bool {
        didSet { save(); updateLaunchAtLogin() }
    }
    @Published public var autoStartMonitoring: Bool {
        didSet { save() }
    }
    @Published public var language: AppLanguage {
        didSet { save(); applyLanguage() }
    }
    @Published public var blockedAppBundleIDs: [String] {
        didSet { save() }
    }
    @Published public var logLevel: StroklyLogLevel {
        didSet { save(); configureLogger() }
    }
    @Published public var fileLoggingEnabled: Bool {
        didSet { save(); configureLogger() }
    }

    private let defaults: UserDefaults
    private let suiteName = "com.luantu.Strokly"

    public init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? UserDefaults(suiteName: "com.luantu.Strokly") ?? .standard
        self.defaults = defaults
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.autoStartMonitoring = defaults.object(forKey: "autoStartMonitoring") as? Bool ?? true
        self.language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .zhHans
        self.blockedAppBundleIDs = defaults.stringArray(forKey: "blockedAppBundleIDs") ?? []
        self.logLevel = StroklyLogLevel(rawValue: defaults.string(forKey: "logLevel") ?? "") ?? .info
        self.fileLoggingEnabled = defaults.object(forKey: "fileLoggingEnabled") as? Bool ?? true
        applyLanguage()
        configureLogger()
    }

    public var locale: Locale {
        Locale(identifier: language.effectiveLocaleIdentifier)
    }

    private func save() {
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(autoStartMonitoring, forKey: "autoStartMonitoring")
        defaults.set(language.rawValue, forKey: "language")
        defaults.set(logLevel.rawValue, forKey: "logLevel")
        defaults.set(fileLoggingEnabled, forKey: "fileLoggingEnabled")
        defaults.set(blockedAppBundleIDs, forKey: "blockedAppBundleIDs")
    }

    private func applyLanguage() {
        let languages: [String]
        if let id = language.localeIdentifier {
            languages = [id]
        } else {
            languages = Locale.preferredLanguages
        }
        defaults.set(languages, forKey: "AppleLanguages")
        UserDefaults.standard.set(languages, forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail
            }
        }
    }

    private func configureLogger() {
        StroklyLogger.shared.configure(level: logLevel, fileLoggingEnabled: fileLoggingEnabled)
    }

    public var logFileURL: URL {
        StroklyLogger.shared.currentLogFileURL
    }

    public func openLogFile() {
        StroklyLogger.shared.info("settings.openLogFile", ["path": logFileURL.path])
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }
}
