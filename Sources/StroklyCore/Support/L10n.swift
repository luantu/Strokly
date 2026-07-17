import Foundation

public enum L10n {
    private static let bundleURL: URL = {
        // 1. .app bundle: look for sidecar resource bundle
        let sidecarPath = Bundle.main.bundlePath + "/Contents/Resources/Strokly_StroklyCore.bundle"
        if let b = Bundle(path: sidecarPath), b.bundleURL.path.hasSuffix(".bundle") {
            return b.bundleURL
        }
        // 2. Command-line / test: bundle next to executable
        let exePath = CommandLine.arguments.first ?? ""
        let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent()
        let bundlePath = exeDir.appendingPathComponent("Strokly_StroklyCore.bundle").path
        if let b = Bundle(path: bundlePath), b.bundleURL.path.hasSuffix(".bundle") {
            return b.bundleURL
        }
        // 3. .app with lproj in Resources directly
        let resPath = Bundle.main.bundlePath + "/Contents/Resources"
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resPath + "/en.lproj", isDirectory: &isDir), isDir.boolValue {
            return URL(fileURLWithPath: resPath)
        }
        // 4. Fallback
        return Bundle.main.bundleURL
    }()

    public static func string(_ key: String) -> String {
        let language = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "zh-Hans"
        let normalized = language.hasPrefix("zh") ? "zh-Hans" : "en"
        let candidates = normalized == "zh-Hans" ? ["zh-Hans", "zh-hans"] : [normalized]

        for candidate in candidates {
            let lprojPath = bundleURL.appendingPathComponent("\(candidate).lproj").path
            if let bundle = Bundle(path: lprojPath) {
                let value = bundle.localizedString(forKey: key, value: key, table: nil)
                if value != key { return value }
            }
        }

        return key
    }
}
