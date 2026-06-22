import Foundation
import Security

protocol ProxmoxServerValidating {
    func validate(url: URL, allowSelfSignedHTTPS: Bool) async throws
}

enum ProxmoxServerValidationError: LocalizedError, Equatable {
    case invalidEndpoint
    case notProxmox
    case httpStatus(Int)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The Proxmox validation endpoint could not be built."
        case .notProxmox:
            return "This does not look like a Proxmox VE server."
        case .httpStatus:
            return "This does not look like a Proxmox VE server."
        case .transport(let message):
            return message.isEmpty ? "This does not look like a Proxmox VE server." : message
        }
    }
}

struct ProxmoxServerValidationService: ProxmoxServerValidating {
    var timeout: TimeInterval = 6

    func validate(url: URL, allowSelfSignedHTTPS: Bool) async throws {
        let validationURL = try Self.validationURL(for: url)
        var request = URLRequest(url: validationURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let delegate = ProxmoxServerValidationDelegate(host: validationURL.host, allowSelfSignedHTTPS: allowSelfSignedHTTPS)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, Self.hasProxmoxServerHeader(httpResponse) {
                return
            }
            if let httpResponse = response as? HTTPURLResponse, !(200...399).contains(httpResponse.statusCode) {
                throw ProxmoxServerValidationError.httpStatus(httpResponse.statusCode)
            }
            guard Self.isValidVersionPayload(data) else {
                throw ProxmoxServerValidationError.notProxmox
            }
        } catch let validationError as ProxmoxServerValidationError {
            throw validationError
        } catch {
            throw ProxmoxServerValidationError.transport((error as NSError).localizedDescription)
        }
    }

    static func validationURL(for url: URL) throws -> URL {
        guard let scheme = url.scheme, let host = url.host else {
            throw ProxmoxServerValidationError.invalidEndpoint
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/api2/json/version"

        guard let validationURL = components.url else {
            throw ProxmoxServerValidationError.invalidEndpoint
        }
        return validationURL
    }

    static func isValidVersionPayload(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(ProxmoxVersionEnvelope.self, from: data) else {
            return false
        }
        return envelope.data.version?.isEmpty == false
    }

    static func hasProxmoxServerHeader(_ response: HTTPURLResponse) -> Bool {
        guard let server = response.value(forHTTPHeaderField: "Server")?.lowercased() else {
            return false
        }

        return server.contains("pve-api-daemon") || server.contains("pveproxy")
    }
}

private struct ProxmoxVersionEnvelope: Decodable {
    var data: ProxmoxVersionData
}

private struct ProxmoxVersionData: Decodable {
    var version: String?
}

private final class ProxmoxServerValidationDelegate: NSObject, URLSessionDelegate {
    private let host: String?
    private let allowSelfSignedHTTPS: Bool

    init(host: String?, allowSelfSignedHTTPS: Bool) {
        self.host = host
        self.allowSelfSignedHTTPS = allowSelfSignedHTTPS
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.caseInsensitiveCompare(host ?? "") == .orderedSame,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }

        if SecTrustEvaluateWithError(trust, nil) {
            return (.performDefaultHandling, nil)
        }

        guard allowSelfSignedHTTPS else {
            return (.performDefaultHandling, nil)
        }

        return (.useCredential, URLCredential(trust: trust))
    }
}
