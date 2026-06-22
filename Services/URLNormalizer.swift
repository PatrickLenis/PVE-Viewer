import Foundation

enum URLNormalizer {
    enum NormalizationError: LocalizedError, Equatable {
        case empty
        case invalid

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Enter a Proxmox host or URL."
            case .invalid:
                return "Enter a valid URL, hostname, IP address, or host:port."
            }
        }
    }

    static func normalize(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NormalizationError.empty }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw NormalizationError.invalid
        }

        let hasScheme = trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
        let candidate = hasScheme ? trimmed : "https://\(trimmed)"

        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              isValidHost(host) else {
            throw NormalizationError.invalid
        }

        components.scheme = scheme
        if !hasScheme && components.port == nil {
            components.port = 8006
        }

        guard let url = components.url else { throw NormalizationError.invalid }
        return url
    }

    private static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253 else { return false }
        if host == "." { return false }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
        guard host.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        guard !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..") else { return false }

        return host.split(separator: ".").allSatisfy { label in
            guard !label.isEmpty, label.count <= 63 else { return false }
            return !label.hasPrefix("-") && !label.hasSuffix("-")
        }
    }
}

