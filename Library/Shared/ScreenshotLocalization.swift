import Foundation
import ObjectiveC

private var screenshotLocalizationBundleKey: UInt8 = 0

private final class ScreenshotBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &screenshotLocalizationBundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

public enum ScreenshotLocalization {
    public static func applyIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard let language = environment["SCREENSHOT_LANGUAGE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !language.isEmpty
        else {
            return
        }
        UserDefaults.standard.set([language], forKey: "AppleLanguages")
        if let locale = environment["SCREENSHOT_LOCALE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !locale.isEmpty
        {
            UserDefaults.standard.set(locale, forKey: "AppleLocale")
        }
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let localizedBundle = Bundle(path: path)
        {
            objc_setAssociatedObject(Bundle.main, &screenshotLocalizationBundleKey, localizedBundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            object_setClass(Bundle.main, ScreenshotBundle.self)
        }
    }
}

private let _screenshotLocalizationApplied: Void = {
    ScreenshotLocalization.applyIfNeeded()
}()
