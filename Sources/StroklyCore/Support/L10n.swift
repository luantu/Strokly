import Foundation

public enum L10n {
    public static func string(_ key: String) -> String {
        let language = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "zh-Hans"
        let normalized = language.hasPrefix("zh") ? "zh-Hans" : "en"
        let candidates = normalized == "zh-Hans" ? ["zh-Hans", "zh-hans"] : [normalized]

        for resourceBundle in [Bundle.main, Bundle.module] {
            for candidate in candidates {
                if let path = resourceBundle.path(forResource: candidate, ofType: "lproj"),
                   let bundle = Bundle(path: path) {
                    let value = bundle.localizedString(forKey: key, value: key, table: nil)
                    if value != key {
                        return value
                    }
                }
            }
        }

        return Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }
}
