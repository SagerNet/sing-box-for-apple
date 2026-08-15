import Foundation

public extension URL {
    var schemeAction: String {
        if let host, !host.isEmpty {
            return host
        }
        var action = path
        if action.isEmpty, let scheme, absoluteString.hasPrefix(scheme + ":") {
            action = String(absoluteString.dropFirst(scheme.count + 1))
        }
        if let queryStart = action.firstIndex(of: "?") {
            action = String(action[action.startIndex ..< queryStart])
        }
        if let fragmentStart = action.firstIndex(of: "#") {
            action = String(action[action.startIndex ..< fragmentStart])
        }
        while action.hasPrefix("/") {
            action.removeFirst()
        }
        return action
    }

    func schemeQueryValue(_ name: String) -> String? {
        if let items = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems {
            return items.first { $0.name == name }?.value
        }
        guard let queryStart = absoluteString.firstIndex(of: "?") else {
            return nil
        }
        let query = String(absoluteString[absoluteString.index(after: queryStart)...])
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == name {
                return String(parts[1]).removingPercentEncoding ?? String(parts[1])
            }
        }
        return nil
    }
}
