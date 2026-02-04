import Foundation
import Libbox

public class HTTPClient {
    private static var userAgent: String {
        var userAgent = Variant.applicationName
        userAgent += "/"
        userAgent += Bundle.main.version
        userAgent += " (Build "
        userAgent += Bundle.main.versionNumber
        userAgent += "; sing-box "
        userAgent += LibboxVersion()
        userAgent += "; language "
        userAgent += Locale.current.identifier
        userAgent += ")"
        return userAgent
    }

    private let client: any LibboxHTTPClientProtocol

    public init() {
        client = LibboxNewHTTPClient()!
        client.modernTLS()
    }

    public func getString(_ url: String?) throws -> String {
        #if DEBUG
            precondition(!Thread.isMainThread, "HTTPClient.getString(...) must not be called on the main thread")
        #endif
        let request = client.newRequest()!
        request.setUserAgent(HTTPClient.userAgent)
        try request.setURL(url)
        let response = try request.execute()
        let content = try response.getContent()
        return content.value
    }

    public func getStringAsync(_ url: String?) async throws -> String {
        try await Self.getStringAsync(url)
    }

    public static func getStringAsync(_ url: String?) async throws -> String {
        try await BlockingIO.run {
            try HTTPClient().getString(url)
        }
    }

    deinit {
        client.close()
    }
}
