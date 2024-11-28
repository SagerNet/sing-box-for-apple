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
        userAgent += ")"
        return userAgent
    }

    private let client: any LibboxHTTPClientProtocol

    public init() {
        client = LibboxNewHTTPClient()!
        client.modernTLS()
    }

    private func _getResponse(_ url: String?) -> HTTPResponse {
        let request = client.newRequest()!
        request.setUserAgent(HTTPClient.userAgent)
        try request.setURL(url)
        return try request.execute()
    }

    public func getString(_ url: String?) throws -> String {
        let response = _getResponse(url)
        var error: NSError?
        let contentString = response.getContentString(&error)
        if let error {
            throw error
        }
        return contentString
    }

    public func getConfigWithUpdatedURL(_ url: String?) throws -> (config: String, newURL: String) {
        let response = _getResponse(url)
        var error: NSError?
        let contentString = response.getContentString(&error)
        if let error {
            throw error
        }
        return (config: contentString, newURL: response.getFinalURL)
    }

    deinit {
        client.close()
    }
}
