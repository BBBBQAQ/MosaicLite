import Foundation

enum L10n {
    static let usesChinese = usesChineseLanguage(Locale.preferredLanguages)

    private static let englishBundle: Bundle = {
        guard let url = Bundle.module.url(forResource: "en", withExtension: "lproj"),
              let bundle = Bundle(url: url)
        else { return .module }
        return bundle
    }()

    static func usesChineseLanguage(_ preferredLanguages: [String]) -> Bool {
        guard let identifier = preferredLanguages.first else { return false }
        return Locale(identifier: identifier).language.languageCode?.identifier == "zh"
    }

    static func tr(_ key: String) -> String {
        tr(key, usesChinese: usesChinese)
    }

    static func tr(_ key: String, usesChinese: Bool) -> String {
        guard !usesChinese else { return key }
        return englishBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: arguments)
    }
}

extension String {
    var localized: String { L10n.tr(self) }
}
