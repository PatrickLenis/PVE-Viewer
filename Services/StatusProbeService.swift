import Foundation
import Security

protocol StatusProbing {
    func status(for instance: ProxmoxInstance) async -> InstanceStatus
}

final class StatusProbeService: NSObject, StatusProbing {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    func status(for instance: ProxmoxInstance) async -> InstanceStatus {
        var request = URLRequest(url: instance.url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let delegate = ProbeSessionDelegate(instance: instance)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer {
            session.invalidateAndCancel()
        }

        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let httpStatus = Self.status(forHTTPStatusCode: httpResponse.statusCode)
                if httpStatus == .online, delegate.acceptedUntrustedServerTrust {
                    return .tlsWarning
                }
                return httpStatus
            }
            return .error
        } catch {
            return Self.status(for: error, allowSelfSignedHTTPS: instance.allowSelfSignedHTTPS)
        }
    }

    static func status(forHTTPStatusCode statusCode: Int) -> InstanceStatus {
        (200...399).contains(statusCode) ? .online : .error
    }

    static func status(for error: URLError) -> InstanceStatus {
        status(for: error as Error, allowSelfSignedHTTPS: false)
    }

    static func status(for error: Error, allowSelfSignedHTTPS: Bool = false) -> InstanceStatus {
        if isTLSCertificateError(error) {
            return allowSelfSignedHTTPS ? .tlsWarning : .error
        }
        if isOffline(error) {
            return .offline
        }
        return .error
    }

    private static func isOffline(_ error: Error) -> Bool {
        guard let urlError = urlError(from: error) else { return false }
        switch urlError.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff,
             .dataNotAllowed, .callIsActive:
            return true
        default:
            return false
        }
    }

    private static func isTLSCertificateError(_ error: Error) -> Bool {
        guard let urlError = urlError(from: error) else { return false }
        switch urlError.code {
        case .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired:
            return true
        default:
            return false
        }
    }

    private static func urlError(from error: Error) -> URLError? {
        if let urlError = error as? URLError {
            return urlError
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return URLError(URLError.Code(rawValue: nsError.code))
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return urlError(from: underlying)
        }

        return nil
    }
}

private final class ProbeSessionDelegate: NSObject, URLSessionDelegate {
    private let instance: ProxmoxInstance
    private(set) var acceptedUntrustedServerTrust = false

    init(instance: ProxmoxInstance) {
        self.instance = instance
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.caseInsensitiveCompare(instance.url.host ?? "") == .orderedSame,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }

        if SecTrustEvaluateWithError(trust, nil) {
            return (.performDefaultHandling, nil)
        }

        guard instance.allowSelfSignedHTTPS else {
            return (.performDefaultHandling, nil)
        }

        acceptedUntrustedServerTrust = true

        return (.useCredential, URLCredential(trust: trust))
    }
}
