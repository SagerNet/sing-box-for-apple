#if !os(tvOS)
    import CryptoKit
    import SwiftUI
    import WebKit

    #if os(iOS)
        import UIKit
    #elseif os(macOS)
        import AppKit
    #endif

    @MainActor
    struct OpenConnectBrowserView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var errorMessage: String?

        let challengeID: String
        let endpointTag: String
        let request: OpenConnectBrowserRequestData
        let onResult: (OpenConnectBrowserResultData) -> Void

        var body: some View {
            VStack(spacing: 0) {
                if let errorMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorMessage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding()
                    .background(Color.red.opacity(0.08))
                }
                OpenConnectWebView(
                    endpointTag: endpointTag,
                    request: request,
                    onResult: onResult,
                    onError: { errorMessage = $0 }
                )
                .id(challengeID)
            }
            .navigationTitle("Authentication")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
        }
    }

    @MainActor
    private final class OpenConnectWebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate,
        WKHTTPCookieStoreObserver
    {
        private enum CompletionMode: Equatable {
            case callback
            case cookies
            case headers
            case invalid
        }

        private struct CookieCandidate {
            let cookie: HTTPCookie
            let sequence: Int
        }

        private final class WeakWebView {
            weak var value: WKWebView?

            init(_ value: WKWebView) {
                self.value = value
            }
        }

        private let request: OpenConnectBrowserRequestData
        private let onResult: (OpenConnectBrowserResultData) -> Void
        private let onError: (String?) -> Void
        private let initialURL: URL?
        private let completionMode: CompletionMode
        private weak var cookieStore: WKHTTPCookieStore?
        private weak var primaryWebView: WKWebView?
        private var popupWebViews: [WeakWebView] = []
        private var completed = false
        private var pendingMainNavigations: Set<ObjectIdentifier> = []
        private var successfulMainResponseURLs: [ObjectIdentifier: String] = [:]
        private var completedFinalURLs: [ObjectIdentifier: URL] = [:]
        private var finalCompletionGeneration = 0
        private var responseHeaders: [String: OpenConnectBrowserHeaderData] = [:]
        private var cookieCandidates: [String: CookieCandidate] = [:]
        private var cookieSequence = 0
        private var cookieSnapshotInFlight = false
        private var cookieSnapshotPending = false

        private static let maximumPopupCount = 8

        init(
            request: OpenConnectBrowserRequestData,
            onResult: @escaping (OpenConnectBrowserResultData) -> Void,
            onError: @escaping (String?) -> Void
        ) {
            self.request = request
            self.onResult = onResult
            self.onError = onError
            initialURL = URL(string: request.url)
            completionMode = Self.completionMode(for: request)
        }

        func begin(in webView: WKWebView) {
            primaryWebView = webView
            guard completionMode != .invalid else {
                DispatchQueue.main.async { [weak self] in
                    self?.fail("The authentication request contains an invalid completion mode.")
                }
                return
            }
            guard let initialURL, Self.isAllowedInitialURL(initialURL) else {
                DispatchQueue.main.async { [weak self] in
                    self?.fail("The authentication request contains an invalid or unsupported URL.")
                }
                return
            }
            let store = webView.configuration.websiteDataStore.httpCookieStore
            guard completionMode == .cookies else {
                activate(store: store)
                return
            }
            let requestedNames = Set(request.cookieNames + request.earlyCookieNames)
            store.getAllCookies { [weak self] cookies in
                DispatchQueue.main.async {
                    guard let self, !self.completed else { return }
                    self.deleteCookies(cookies.filter { requestedNames.contains($0.name) }, from: store) {
                        self.activate(store: store)
                    }
                }
            }
        }

        private func activate(store: WKHTTPCookieStore) {
            cookieStore?.remove(self)
            cookieStore = store
            store.add(self)
            guard let primaryWebView, let initialURL else { return }
            primaryWebView.load(URLRequest(url: initialURL))
        }

        private func deleteCookies(
            _ cookies: [HTTPCookie],
            from store: WKHTTPCookieStore,
            completion: @escaping () -> Void
        ) {
            guard let cookie = cookies.first else {
                completion()
                return
            }
            let remainingCookies = Array(cookies.dropFirst())
            store.delete(cookie) { [weak self] in
                DispatchQueue.main.async {
                    guard let self, !self.completed else { return }
                    self.deleteCookies(remainingCookies, from: store, completion: completion)
                }
            }
        }

        func detach(from webView: WKWebView) {
            completed = true
            cookieStore?.remove(self)
            cookieStore = nil
            for popupWebView in popupWebViews.compactMap(\.value) {
                popupWebView.stopLoading()
                popupWebView.navigationDelegate = nil
                popupWebView.uiDelegate = nil
                popupWebView.removeFromSuperview()
            }
            popupWebViews.removeAll()
            pendingMainNavigations.removeAll()
            successfulMainResponseURLs.removeAll()
            completedFinalURLs.removeAll()
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                fail("The authentication page attempted to open an invalid URL.")
                decisionHandler(.cancel)
                return
            }
            let isTopLevelNavigation = navigationAction.targetFrame?.isMainFrame != false
            if isTopLevelNavigation, matchesCallback(url) {
                decisionHandler(.cancel)
                complete(OpenConnectBrowserResultData(finalURL: url.absoluteString, cookies: [], headers: []))
                return
            }
            guard Self.isAllowedNavigationURL(url) else {
                fail("The authentication page attempted to open an unsupported URL scheme: \(url.scheme ?? "unknown").")
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame?.isMainFrame == true {
                clearNavigationState(for: webView)
                pendingMainNavigations.insert(ObjectIdentifier(webView))
                reportError(nil)
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if navigationResponse.isForMainFrame {
                pendingMainNavigations.remove(ObjectIdentifier(webView))
                if let response = navigationResponse.response as? HTTPURLResponse,
                   let url = response.url
                {
                    if response.statusCode >= 400 {
                        clearNavigationState(for: webView)
                        fail("The authentication page returned HTTP \(response.statusCode).")
                        decisionHandler(.cancel)
                        return
                    } else {
                        successfulMainResponseURLs[ObjectIdentifier(webView)] = url.absoluteString
                        handleHeaders(response)
                    }
                }
            }
            captureCookies()
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation?) {
            guard let url = webView.url else { return }
            let webViewID = ObjectIdentifier(webView)
            if successfulMainResponseURLs.removeValue(forKey: webViewID) == url.absoluteString,
               completionMode == .cookies,
               url.absoluteString == request.finalURL
            {
                completedFinalURLs[webViewID] = url
                finalCompletionGeneration += 1
            } else {
                clearCompletedFinalURL(for: webView)
            }
            captureCookies()
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation?, withError error: Error) {
            clearNavigationState(for: webView)
            reportNavigationError(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation?, withError error: Error) {
            clearNavigationState(for: webView)
            reportNavigationError(error)
        }

        func webView(
            _: WKWebView,
            didReceive _: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            completionHandler(.performDefaultHandling, nil)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            clearNavigationState(for: webView)
            fail("The authentication web page stopped unexpectedly. Close it and try again.")
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures _: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url, matchesCallback(url) {
                complete(OpenConnectBrowserResultData(finalURL: url.absoluteString, cookies: [], headers: []))
                return nil
            }
            guard navigationAction.targetFrame == nil else { return nil }
            guard let url = navigationAction.request.url, Self.isAllowedNavigationURL(url) else {
                fail("The authentication page attempted to open an unsupported popup URL.")
                return nil
            }
            popupWebViews.removeAll { $0.value == nil }
            guard popupWebViews.count < Self.maximumPopupCount else {
                fail("The authentication page opened too many popup windows.")
                return nil
            }
            configuration.websiteDataStore = webView.configuration.websiteDataStore
            let popupWebView = WKWebView(frame: webView.bounds, configuration: configuration)
            popupWebView.navigationDelegate = self
            popupWebView.uiDelegate = self
            #if os(iOS)
                popupWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            #elseif os(macOS)
                popupWebView.autoresizingMask = [.width, .height]
            #endif
            webView.addSubview(popupWebView)
            popupWebViews.append(WeakWebView(popupWebView))
            return popupWebView
        }

        func webViewDidClose(_ webView: WKWebView) {
            if webView === primaryWebView {
                clearNavigationState(for: webView)
                fail("The authentication page closed before authentication completed.")
                return
            }
            clearNavigationState(for: webView)
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.removeFromSuperview()
            popupWebViews.removeAll { $0.value == nil || $0.value === webView }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            presentJavaScriptAlert(
                on: webView,
                message: javaScriptMessage(message, frame: frame),
                completionHandler: completionHandler
            )
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            presentJavaScriptConfirm(
                on: webView,
                message: javaScriptMessage(message, frame: frame),
                completionHandler: completionHandler
            )
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            presentJavaScriptPrompt(
                on: webView,
                prompt: javaScriptMessage(prompt, frame: frame),
                defaultText: defaultText,
                completionHandler: completionHandler
            )
        }

        func cookiesDidChange(in _: WKHTTPCookieStore) {
            captureCookies()
        }

        private func javaScriptMessage(_ message: String, frame: WKFrameInfo) -> String {
            guard let host = frame.request.url?.host, !host.isEmpty else { return message }
            return "\(host)\n\n\(message)"
        }

        private func matchesCallback(_ url: URL) -> Bool {
            guard completionMode == .callback else { return false }
            let absoluteURL = url.absoluteString
            return request.callbackURLPrefixes.contains { !$0.isEmpty && absoluteURL.hasPrefix($0) }
        }

        private static func completionMode(for request: OpenConnectBrowserRequestData) -> CompletionMode {
            if !request.callbackURLPrefixes.isEmpty,
               request.finalURL.isEmpty,
               request.cookieNames.isEmpty,
               request.earlyCookieNames.isEmpty,
               request.headerNames.isEmpty,
               request.callbackURLPrefixes.allSatisfy({ !$0.isEmpty }),
               Set(request.callbackURLPrefixes).count == request.callbackURLPrefixes.count
            {
                return .callback
            }
            if request.callbackURLPrefixes.isEmpty,
               !request.finalURL.isEmpty,
               !request.cookieNames.isEmpty,
               request.headerNames.isEmpty,
               request.cookieNames.allSatisfy({ !$0.isEmpty }),
               request.earlyCookieNames.allSatisfy({ !$0.isEmpty }),
               Set(request.cookieNames).count == request.cookieNames.count,
               Set(request.earlyCookieNames).count == request.earlyCookieNames.count,
               Set(request.cookieNames).isDisjoint(with: request.earlyCookieNames)
            {
                return .cookies
            }
            if request.callbackURLPrefixes.isEmpty,
               request.finalURL.isEmpty,
               request.cookieNames.isEmpty,
               request.earlyCookieNames.isEmpty,
               !request.headerNames.isEmpty,
               request.headerNames.allSatisfy({ !$0.isEmpty }),
               Set(request.headerNames.map { $0.lowercased() }).count == request.headerNames.count
            {
                return .headers
            }
            return .invalid
        }

        private static func isAllowedInitialURL(_ url: URL) -> Bool {
            switch url.scheme?.lowercased() {
            case "http", "https":
                return url.host != nil
            case "data":
                return true
            default:
                return false
            }
        }

        private static func isAllowedNavigationURL(_ url: URL) -> Bool {
            switch url.scheme?.lowercased() {
            case "http", "https":
                return url.host != nil
            case "data", "about", "blob":
                return true
            default:
                return false
            }
        }

        private func handleHeaders(_ response: HTTPURLResponse) {
            guard !completed, completionMode == .headers else { return }
            let requestedNames = Dictionary(
                request.headerNames.map { ($0.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for (key, value) in response.allHeaderFields {
                let responseName = String(describing: key)
                let lowercasedName = responseName.lowercased()
                guard let requestedName = requestedNames[lowercasedName] else { continue }
                let values: [String]
                if let stringValues = value as? [String] {
                    values = stringValues.filter { !$0.isEmpty }
                } else {
                    let stringValue = String(describing: value)
                    values = stringValue.isEmpty ? [] : [stringValue]
                }
                guard !values.isEmpty else { continue }
                responseHeaders[lowercasedName] = OpenConnectBrowserHeaderData(name: requestedName, values: values)
            }
            let headers = accumulatedHeaders()
            guard headersAreReady(headers) else { return }
            complete(OpenConnectBrowserResultData(finalURL: "", cookies: [], headers: headers))
        }

        private func accumulatedHeaders() -> [OpenConnectBrowserHeaderData] {
            var includedNames: Set<String> = []
            return request.headerNames.compactMap { requestedName in
                let lowercasedName = requestedName.lowercased()
                guard includedNames.insert(lowercasedName).inserted else { return nil }
                return responseHeaders[lowercasedName]
            }
        }

        private func captureCookies() {
            guard !completed, completionMode == .cookies, let cookieStore else { return }
            if cookieSnapshotInFlight {
                cookieSnapshotPending = true
                return
            }
            cookieSnapshotInFlight = true
            let startedAfterFinalGeneration = completedFinalURLs.isEmpty ? nil : finalCompletionGeneration
            cookieStore.getAllCookies { [weak self] cookies in
                DispatchQueue.main.async {
                    guard let self, !self.completed else { return }
                    self.processCookies(cookies)
                    self.cookieSnapshotInFlight = false
                    if self.completeEarlyCookieIfPresent() {
                        return
                    }
                    if startedAfterFinalGeneration == self.finalCompletionGeneration,
                       self.completeNormalCookieResultIfReady()
                    {
                        return
                    }
                    if self.cookieSnapshotPending {
                        self.cookieSnapshotPending = false
                        self.captureCookies()
                    }
                }
            }
        }

        private func processCookies(_ cookies: [HTTPCookie]) {
            let requestedNames = Set(request.cookieNames + request.earlyCookieNames)
            let liveKeys = Set(cookies.compactMap { cookie -> String? in
                guard requestedNames.contains(cookie.name), !cookie.value.isEmpty,
                      cookie.expiresDate.map({ $0 > Date() }) ?? true
                else {
                    return nil
                }
                return Self.cookieKey(cookie)
            })
            cookieCandidates = cookieCandidates.filter { liveKeys.contains($0.key) }
            for cookie in cookies {
                guard requestedNames.contains(cookie.name), !cookie.value.isEmpty,
                      cookie.expiresDate.map({ $0 > Date() }) ?? true
                else {
                    continue
                }
                let key = Self.cookieKey(cookie)
                if let existingCandidate = cookieCandidates[key],
                   existingCandidate.cookie.value == cookie.value,
                   existingCandidate.cookie.isSecure == cookie.isSecure,
                   existingCandidate.cookie.expiresDate == cookie.expiresDate
                {
                    continue
                }
                cookieSequence += 1
                cookieCandidates[key] = CookieCandidate(cookie: cookie, sequence: cookieSequence)
            }
        }

        private static func cookieKey(_ cookie: HTTPCookie) -> String {
            [cookie.name, cookie.domain.lowercased(), cookie.path].joined(separator: "\u{0}")
        }

        @discardableResult
        private func completeNormalCookieResultIfReady() -> Bool {
            guard let completedFinalURL = completedFinalURLs.values.first else { return false }
            let cookies = accumulatedCookieResult(preferredURL: completedFinalURL)
            guard !cookies.isEmpty else { return false }
            complete(OpenConnectBrowserResultData(
                finalURL: request.finalURL,
                cookies: cookies,
                headers: []
            ))
            return true
        }

        @discardableResult
        private func completeEarlyCookieIfPresent() -> Bool {
            guard pendingMainNavigations.isEmpty else { return false }
            guard let earlyCookie = earlyCookieResult() else { return false }
            complete(OpenConnectBrowserResultData(finalURL: "", cookies: [earlyCookie], headers: []))
            return true
        }

        private func earlyCookieResult() -> OpenConnectBrowserCookieData? {
            for name in request.earlyCookieNames {
                let candidate = cookieCandidates.values
                    .filter { $0.cookie.name == name && !$0.cookie.value.isEmpty }
                    .max { $0.sequence < $1.sequence }
                if let candidate {
                    return OpenConnectBrowserCookieData(name: candidate.cookie.name, value: candidate.cookie.value)
                }
            }
            return nil
        }

        private func headersAreReady(_ headers: [OpenConnectBrowserHeaderData]) -> Bool {
            guard !request.headerNames.isEmpty else { return true }
            let names = Set(headers.map { $0.name.lowercased() })
            let requestedNames = Set(request.headerNames.map { $0.lowercased() })
            if requestedNames.contains("saml-username"),
               requestedNames.contains("prelogin-cookie"),
               requestedNames.contains("portal-userauthcookie")
            {
                return names.contains("saml-username") &&
                    (names.contains("prelogin-cookie") || names.contains("portal-userauthcookie"))
            }
            return requestedNames.isSubset(of: names)
        }

        private func accumulatedCookieResult(preferredURL: URL?) -> [OpenConnectBrowserCookieData] {
            var includedNames: Set<String> = []
            return request.cookieNames.compactMap { requestedName in
                guard includedNames.insert(requestedName).inserted,
                      let candidate = bestCookie(named: requestedName, preferredURL: preferredURL)
                else {
                    return nil
                }
                return OpenConnectBrowserCookieData(name: candidate.cookie.name, value: candidate.cookie.value)
            }
        }

        private func bestCookie(named name: String, preferredURL: URL?) -> CookieCandidate? {
            let rankedURLs = [preferredURL, URL(string: request.finalURL), initialURL]
                .compactMap { $0 }
                .reduce(into: [URL]()) { result, url in
                    if !result.contains(where: { $0.absoluteString == url.absoluteString }) {
                        result.append(url)
                    }
                }
            let candidates = cookieCandidates.values.filter {
                $0.cookie.name == name && !$0.cookie.value.isEmpty
            }
            return candidates.sorted { lhs, rhs in
                let lhsRank = Self.cookieURLRank(lhs.cookie, urls: rankedURLs)
                let rhsRank = Self.cookieURLRank(rhs.cookie, urls: rankedURLs)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                if lhsRank == Int.max, lhs.sequence != rhs.sequence {
                    return lhs.sequence > rhs.sequence
                }
                if lhs.cookie.path.count != rhs.cookie.path.count {
                    return lhs.cookie.path.count > rhs.cookie.path.count
                }
                let lhsDomain = lhs.cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                let rhsDomain = rhs.cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if lhsDomain.count != rhsDomain.count {
                    return lhsDomain.count > rhsDomain.count
                }
                if lhs.sequence != rhs.sequence {
                    return lhs.sequence > rhs.sequence
                }
                let lhsKey = Self.cookieKey(lhs.cookie)
                let rhsKey = Self.cookieKey(rhs.cookie)
                if lhsKey != rhsKey {
                    return lhsKey < rhsKey
                }
                return lhs.cookie.value < rhs.cookie.value
            }.first
        }

        private static func cookieURLRank(_ cookie: HTTPCookie, urls: [URL]) -> Int {
            urls.firstIndex(where: cookie.matches(url:)) ?? Int.max
        }

        private func clearNavigationState(for webView: WKWebView) {
            pendingMainNavigations.remove(ObjectIdentifier(webView))
            successfulMainResponseURLs.removeValue(forKey: ObjectIdentifier(webView))
            clearCompletedFinalURL(for: webView)
        }

        private func clearCompletedFinalURL(for webView: WKWebView) {
            if completedFinalURLs.removeValue(forKey: ObjectIdentifier(webView)) != nil {
                finalCompletionGeneration += 1
            }
        }

        private func complete(_ result: OpenConnectBrowserResultData) {
            guard !completed else { return }
            completed = true
            cookieStore?.remove(self)
            onResult(result)
        }

        private func reportNavigationError(_ error: Error) {
            let cocoaError = error as NSError
            guard cocoaError.code != NSURLErrorCancelled else { return }
            fail("Authentication page failed to load: \(error.localizedDescription)")
        }

        private func fail(_ message: String) {
            guard !completed else { return }
            completed = true
            cookieStore?.remove(self)
            onError(message)
        }

        private func reportError(_ message: String?) {
            guard !completed else { return }
            onError(message)
        }

        #if os(iOS)
            private func presentJavaScriptAlert(
                on webView: WKWebView,
                message: String,
                completionHandler: @escaping () -> Void
            ) {
                guard let viewController = webView.enclosingViewController else {
                    reportError(message)
                    completionHandler()
                    return
                }
                let alert = UIAlertController(title: "Website Message", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
                viewController.present(alert, animated: true)
            }

            private func presentJavaScriptConfirm(
                on webView: WKWebView,
                message: String,
                completionHandler: @escaping (Bool) -> Void
            ) {
                guard let viewController = webView.enclosingViewController else {
                    reportError(message)
                    completionHandler(false)
                    return
                }
                let alert = UIAlertController(title: "Website Message", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
                viewController.present(alert, animated: true)
            }

            private func presentJavaScriptPrompt(
                on webView: WKWebView,
                prompt: String,
                defaultText: String?,
                completionHandler: @escaping (String?) -> Void
            ) {
                guard let viewController = webView.enclosingViewController else {
                    reportError(prompt)
                    completionHandler(nil)
                    return
                }
                let alert = UIAlertController(title: "Website Message", message: prompt, preferredStyle: .alert)
                alert.addTextField { textField in textField.text = defaultText }
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    completionHandler(alert.textFields?.first?.text)
                })
                viewController.present(alert, animated: true)
            }
        #elseif os(macOS)
            private func presentJavaScriptAlert(
                on webView: WKWebView,
                message: String,
                completionHandler: @escaping () -> Void
            ) {
                let alert = NSAlert()
                alert.messageText = "Website Message"
                alert.informativeText = message
                alert.addButton(withTitle: "OK")
                present(alert: alert, on: webView) { _ in completionHandler() }
            }

            private func presentJavaScriptConfirm(
                on webView: WKWebView,
                message: String,
                completionHandler: @escaping (Bool) -> Void
            ) {
                let alert = NSAlert()
                alert.messageText = "Website Message"
                alert.informativeText = message
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")
                present(alert: alert, on: webView) { response in
                    completionHandler(response == .alertFirstButtonReturn)
                }
            }

            private func presentJavaScriptPrompt(
                on webView: WKWebView,
                prompt: String,
                defaultText: String?,
                completionHandler: @escaping (String?) -> Void
            ) {
                let alert = NSAlert()
                alert.messageText = "Website Message"
                alert.informativeText = prompt
                let textField = NSTextField(string: defaultText ?? "")
                textField.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
                alert.accessoryView = textField
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")
                present(alert: alert, on: webView) { response in
                    completionHandler(response == .alertFirstButtonReturn ? textField.stringValue : nil)
                }
            }

            private func present(
                alert: NSAlert,
                on webView: WKWebView,
                completionHandler: @escaping (NSApplication.ModalResponse) -> Void
            ) {
                if let window = webView.window {
                    alert.beginSheetModal(for: window, completionHandler: completionHandler)
                } else {
                    completionHandler(alert.runModal())
                }
            }
        #endif
    }

    private extension HTTPCookie {
        func matches(url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            let normalizedDomain = domain.lowercased()
            let isDomainCookie = normalizedDomain.hasPrefix(".")
            let cookieDomain = normalizedDomain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !cookieDomain.isEmpty,
                  host == cookieDomain || (isDomainCookie && host.hasSuffix("." + cookieDomain))
            else {
                return false
            }

            let requestPath = url.path.isEmpty ? "/" : url.path
            let cookiePath = path.isEmpty ? "/" : path
            let pathMatches = requestPath == cookiePath ||
                (requestPath.hasPrefix(cookiePath) &&
                    (cookiePath.hasSuffix("/") || requestPath.dropFirst(cookiePath.count).first == "/"))
            guard pathMatches else { return false }
            guard !isSecure || url.scheme?.lowercased() == "https" else { return false }
            guard let expiresDate else { return true }
            return expiresDate > Date()
        }
    }

    #if os(iOS)
        private extension UIView {
            var enclosingViewController: UIViewController? {
                var currentResponder: UIResponder? = self
                while let responder = currentResponder {
                    if let viewController = responder as? UIViewController {
                        return viewController
                    }
                    currentResponder = responder.next
                }
                return nil
            }
        }
    #endif

    @MainActor
    private func makeWebView(
        coordinator: OpenConnectWebViewCoordinator,
        endpointTag: String,
        cacheID: String
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = browserDataStore(
            for: cacheID.isEmpty ? endpointTag : "\(cacheID):\(endpointTag)"
        )
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinator.begin(in: webView)
        return webView
    }

    @MainActor
    private func browserDataStore(for storageKey: String) -> WKWebsiteDataStore {
        if #available(iOS 17.0, macOS 14.0, *) {
            return WKWebsiteDataStore(forIdentifier: browserDataStoreIdentifier(for: storageKey))
        } else {
            return .default()
        }
    }

    private func browserDataStoreIdentifier(for storageKey: String) -> UUID {
        var digest = Array(SHA256.hash(data: Data("openconnect-browser:\(storageKey)".utf8)))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }

    #if os(iOS)
        private struct OpenConnectWebView: UIViewRepresentable {
            let endpointTag: String
            let request: OpenConnectBrowserRequestData
            let onResult: (OpenConnectBrowserResultData) -> Void
            let onError: (String?) -> Void

            func makeCoordinator() -> OpenConnectWebViewCoordinator {
                OpenConnectWebViewCoordinator(request: request, onResult: onResult, onError: onError)
            }

            func makeUIView(context: Context) -> WKWebView {
                makeWebView(coordinator: context.coordinator, endpointTag: endpointTag, cacheID: request.cacheID)
            }

            func updateUIView(_: WKWebView, context _: Context) {}

            static func dismantleUIView(_ uiView: WKWebView, coordinator: OpenConnectWebViewCoordinator) {
                coordinator.detach(from: uiView)
            }
        }
    #elseif os(macOS)
        private struct OpenConnectWebView: NSViewRepresentable {
            let endpointTag: String
            let request: OpenConnectBrowserRequestData
            let onResult: (OpenConnectBrowserResultData) -> Void
            let onError: (String?) -> Void

            func makeCoordinator() -> OpenConnectWebViewCoordinator {
                OpenConnectWebViewCoordinator(request: request, onResult: onResult, onError: onError)
            }

            func makeNSView(context: Context) -> WKWebView {
                makeWebView(coordinator: context.coordinator, endpointTag: endpointTag, cacheID: request.cacheID)
            }

            func updateNSView(_: WKWebView, context _: Context) {}

            static func dismantleNSView(_ nsView: WKWebView, coordinator: OpenConnectWebViewCoordinator) {
                coordinator.detach(from: nsView)
            }
        }
    #endif
#endif
