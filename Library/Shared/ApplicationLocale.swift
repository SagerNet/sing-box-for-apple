import Foundation
import Libbox

public enum ApplicationLocale {
    private static let appleLanguagesKey = "AppleLanguages"

    public static var selectedIdentifier: String? {
        let defaults = UserDefaults.standard
        if let identifier = firstLanguageIdentifier(
            in: defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        ) {
            return identifier
        }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let applicationDomain = defaults.persistentDomain(forName: bundleIdentifier)
        else {
            return nil
        }
        return firstLanguageIdentifier(in: applicationDomain)
    }

    public static var preferredIdentifier: String {
        if let selectedIdentifier {
            return selectedIdentifier
        }
        if let systemIdentifier = Locale.preferredLanguages.first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !systemIdentifier.isEmpty
        {
            return systemIdentifier
        }
        return Locale.current.identifier
    }

    public static func setSelectedIdentifier(_ identifier: String?) {
        guard let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty
        else {
            UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
            return
        }
        UserDefaults.standard.set(
            [Locale.canonicalLanguageIdentifier(from: identifier)],
            forKey: appleLanguagesKey
        )
    }

    public static func apply(_ identifier: String? = nil) throws {
        let identifier = identifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var localeError: NSError?
        LibboxSetLocale(
            identifier.flatMap { $0.isEmpty ? nil : $0 } ?? preferredIdentifier,
            &localeError
        )
        if let localeError {
            throw localeError
        }
    }

    private static func firstLanguageIdentifier(in domain: [String: Any]) -> String? {
        guard let languages = domain[appleLanguagesKey] as? [String],
              let identifier = languages.first?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty
        else {
            return nil
        }
        return identifier
    }
}
