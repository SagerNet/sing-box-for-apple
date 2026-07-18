#if !os(tvOS)
    import SwiftUI
    import WebKit

    @MainActor
    struct OpenConnectBrowserView: View {
        @Environment(\.dismiss) private var dismiss
        let request: OpenConnectBrowserRequestData
        let onResult: (OpenConnectBrowserResultData) -> Void

        var body: some View {
            OpenConnectWebView(request: request, onResult: onResult)
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

    private final class OpenConnectWebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let request: OpenConnectBrowserRequestData
        private let onResult: (OpenConnectBrowserResultData) -> Void
        private var completed = false

        init(request: OpenConnectBrowserRequestData, onResult: @escaping (OpenConnectBrowserResultData) -> Void) {
            self.request = request
            self.onResult = onResult
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if navigationResponse.isForMainFrame,
               let response = navigationResponse.response as? HTTPURLResponse,
               let url = response.url
            {
                handleHeaders(url: url, response: response)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation?) {
            guard let url = webView.url, url.absoluteString == request.finalURL else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                DispatchQueue.main.async {
                    self?.handleCookies(url: url, cookies: cookies)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith _: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures _: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func handleHeaders(url: URL, response: HTTPURLResponse) {
            guard !completed, !request.headerNames.isEmpty else { return }
            let requestedNames = Set(request.headerNames.map { $0.lowercased() })
            var headers: [OpenConnectBrowserHeaderData] = []
            for (key, value) in response.allHeaderFields {
                let name = String(describing: key)
                guard requestedNames.contains(name.lowercased()) else { continue }
                let values: [String]
                if let stringValues = value as? [String] {
                    values = stringValues
                } else {
                    values = [String(describing: value)]
                }
                headers.append(OpenConnectBrowserHeaderData(name: name, values: values))
            }
            let responseNames = Set(headers.map { $0.name.lowercased() })
            guard responseNames.contains("saml-username"),
                  responseNames.contains("prelogin-cookie") || responseNames.contains("portal-userauthcookie")
            else {
                return
            }
            complete(OpenConnectBrowserResultData(finalURL: url.absoluteString, cookies: [], headers: headers))
        }

        private func handleCookies(url: URL, cookies: [HTTPCookie]) {
            guard !completed else { return }
            let requestedNames = Set(request.cookieNames)
            let matchedCookies = cookies.compactMap { cookie -> OpenConnectBrowserCookieData? in
                guard requestedNames.contains(cookie.name), cookie.matches(url: url) else { return nil }
                return OpenConnectBrowserCookieData(name: cookie.name, value: cookie.value)
            }
            guard request.cookieNames.isEmpty || !matchedCookies.isEmpty else { return }
            complete(OpenConnectBrowserResultData(finalURL: url.absoluteString, cookies: matchedCookies, headers: []))
        }

        private func complete(_ result: OpenConnectBrowserResultData) {
            guard !completed else { return }
            completed = true
            onResult(result)
        }
    }

    private extension HTTPCookie {
        func matches(url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            let cookieDomain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard host == cookieDomain || host.hasSuffix("." + cookieDomain) else { return false }
            guard url.path.isEmpty || url.path.hasPrefix(path) else { return false }
            return !isSecure || url.scheme?.lowercased() == "https"
        }
    }

    private func makeWebView(
        coordinator: OpenConnectWebViewCoordinator,
        request: OpenConnectBrowserRequestData
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        if let url = URL(string: request.url) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    #if os(iOS)
        private struct OpenConnectWebView: UIViewRepresentable {
            let request: OpenConnectBrowserRequestData
            let onResult: (OpenConnectBrowserResultData) -> Void

            func makeCoordinator() -> OpenConnectWebViewCoordinator {
                OpenConnectWebViewCoordinator(request: request, onResult: onResult)
            }

            func makeUIView(context: Context) -> WKWebView {
                makeWebView(coordinator: context.coordinator, request: request)
            }

            func updateUIView(_: WKWebView, context _: Context) {}
        }
    #elseif os(macOS)
        private struct OpenConnectWebView: NSViewRepresentable {
            let request: OpenConnectBrowserRequestData
            let onResult: (OpenConnectBrowserResultData) -> Void

            func makeCoordinator() -> OpenConnectWebViewCoordinator {
                OpenConnectWebViewCoordinator(request: request, onResult: onResult)
            }

            func makeNSView(context: Context) -> WKWebView {
                makeWebView(coordinator: context.coordinator, request: request)
            }

            func updateNSView(_: WKWebView, context _: Context) {}
        }
    #endif
#endif
