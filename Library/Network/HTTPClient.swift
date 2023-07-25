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

    public func getString(_ url: String?) throws -> String {
        let request = client.newRequest()!
        request.setUserAgent(HTTPClient.userAgent)
        try request.setURL(url)
        let response = try request.execute()
        var error: NSError?
        let contentString = response.getContentString(&error)
        if let error {
            throw error
        }
        return contentString
    }

    deinit {
        client.close()
    }
}
