import SwiftUI
import WebKit
import Security

struct WebViewCommand: Equatable {
    let id: UUID
    let action: Action

    enum Action: Equatable {
        case none
        case reload
    }

    init(id: UUID = UUID(), action: Action = .none) {
        self.id = id
        self.action = action
    }

    static func reload() -> WebViewCommand {
        WebViewCommand(action: .reload)
    }
}

struct ProxmoxWebView: NSViewRepresentable {
    let instance: ProxmoxInstance
    @Binding var command: WebViewCommand

    func makeCoordinator() -> Coordinator {
        Coordinator(instance: instance)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: instance.url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let previousInstance = context.coordinator.instance
        context.coordinator.instance = instance

        let urlChanged = webView.url != instance.url && webView.url?.host != instance.url.host
        let tlsPolicyChanged = previousInstance.allowSelfSignedHTTPS != instance.allowSelfSignedHTTPS
        if urlChanged || tlsPolicyChanged {
            webView.stopLoading()
            webView.load(URLRequest(url: instance.url))
        }

        if command.action == .reload {
            webView.reload()
            DispatchQueue.main.async {
                command = WebViewCommand()
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var instance: ProxmoxInstance

        init(instance: ProxmoxInstance) {
            self.instance = instance
        }

        func webView(
            _ webView: WKWebView,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  challenge.protectionSpace.host.caseInsensitiveCompare(instance.url.host ?? "") == .orderedSame,
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            if SecTrustEvaluateWithError(trust, nil) {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            guard instance.allowSelfSignedHTTPS else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            completionHandler(.useCredential, URLCredential(trust: trust))
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            guard let response = navigationResponse.response as? HTTPURLResponse,
                  !(200...399).contains(response.statusCode) else {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
            webView.loadHTMLString(
                Self.errorHTML(
                    title: "Page Error",
                    message: "The Proxmox web UI returned HTTP \(response.statusCode)."
                ),
                baseURL: nil
            )
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            guard !Self.isCancelled(error) else { return }

            let message: String
            if Self.isTLSCertificateError(error), !instance.allowSelfSignedHTTPS {
                let host = instance.url.host ?? instance.url.absoluteString
                message = "\(host) uses an untrusted HTTPS certificate. Enable Allow self-signed HTTPS for this instance to load it."
            } else {
                message = Self.summary(for: error)
            }

            webView.loadHTMLString(
                Self.errorHTML(title: "Connection Error", message: message),
                baseURL: nil
            )
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            guard !Self.isCancelled(error) else { return }
            webView.loadHTMLString(
                Self.errorHTML(title: "Page Error", message: Self.summary(for: error)),
                baseURL: nil
            )
        }

        private static func isTLSCertificateError(_ error: Error) -> Bool {
            let nsError = error as NSError
            guard nsError.domain == NSURLErrorDomain else { return false }

            switch URLError.Code(rawValue: nsError.code) {
            case .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
                 .clientCertificateRejected, .clientCertificateRequired,
                 .secureConnectionFailed:
                return true
            default:
                return false
            }
        }

        private static func isCancelled(_ error: Error) -> Bool {
            let nsError = error as NSError
            return nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue
        }

        private static func summary(for error: Error) -> String {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                switch URLError.Code(rawValue: nsError.code) {
                case .timedOut:
                    return "The connection timed out."
                case .cannotFindHost, .dnsLookupFailed:
                    return "The host could not be found."
                case .cannotConnectToHost:
                    return "The host refused the connection."
                case .notConnectedToInternet:
                    return "This Mac is not connected to the network."
                case .serverCertificateUntrusted, .serverCertificateHasBadDate,
                     .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
                     .clientCertificateRejected, .clientCertificateRequired,
                     .secureConnectionFailed:
                    return "The HTTPS certificate could not be trusted."
                default:
                    break
                }
            }
            return nsError.localizedDescription
        }

        private static func errorHTML(title: String, message: String) -> String {
            return """
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8">
              <style>
                :root { color-scheme: light dark; }
                html {
                  background: #111111;
                  min-height: 100%;
                }
                body {
                  align-items: center;
                  background: #111111;
                  color: #f5f5f5;
                  display: flex;
                  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                  min-height: 100vh;
                  justify-content: center;
                  margin: 0;
                }
                main {
                  box-sizing: border-box;
                  max-width: 460px;
                  padding: 32px;
                  text-align: center;
                }
                h1 {
                  font-size: 22px;
                  font-weight: 650;
                  letter-spacing: 0;
                  line-height: 1.2;
                  margin: 0 0 10px;
                }
                p {
                  color: #b8b8b8;
                  font-size: 14px;
                  line-height: 1.45;
                  margin: 0;
                }
                @media (prefers-color-scheme: light) {
                  html,
                  body {
                    background: #f5f5f5;
                    color: #1d1d1f;
                  }
                  p {
                    color: #555555;
                  }
                }
              </style>
            </head>
            <body>
              <main>
                <h1>\(escapeHTML(title))</h1>
                <p>\(escapeHTML(message))</p>
              </main>
            </body>
            </html>
            """
        }

        private static func escapeHTML(_ value: String) -> String {
            value
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        }
    }
}
