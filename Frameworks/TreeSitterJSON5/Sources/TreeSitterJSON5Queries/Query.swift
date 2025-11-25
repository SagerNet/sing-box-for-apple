import Foundation

public enum Query {
    public static var highlightsFileURL: URL {
        url(named: "highlights")
    }

    public static var injectionsFileURL: URL {
        url(named: "injections")
    }
}

private extension Query {
    static func url(named filename: String) -> URL {
        Bundle.module.url(forResource: filename, withExtension: "scm")!
    }
}
