import Foundation
import SwiftUI

struct ProxmoxInstance: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var url: URL
    var allowSelfSignedHTTPS: Bool
    var hasAPIToken: Bool
    var apiDisplayName: String?

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        allowSelfSignedHTTPS: Bool = false,
        hasAPIToken: Bool = false,
        apiDisplayName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.allowSelfSignedHTTPS = allowSelfSignedHTTPS
        self.hasAPIToken = hasAPIToken
        self.apiDisplayName = apiDisplayName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case allowSelfSignedHTTPS
        case hasAPIToken
        case apiDisplayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(URL.self, forKey: .url)
        allowSelfSignedHTTPS = try container.decode(Bool.self, forKey: .allowSelfSignedHTTPS)
        hasAPIToken = try container.decodeIfPresent(Bool.self, forKey: .hasAPIToken) ?? false
        apiDisplayName = try container.decodeIfPresent(String.self, forKey: .apiDisplayName)
    }
}

enum InstanceStatus: String, Codable, Equatable {
    case unknown
    case offline
    case tlsWarning
    case error
    case online

    var color: Color {
        switch self {
        case .unknown, .offline:
            return .secondary.opacity(0.7)
        case .tlsWarning:
            return .yellow
        case .error:
            return .red
        case .online:
            return .green
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .offline:
            return "Offline"
        case .tlsWarning:
            return "TLS warning"
        case .error:
            return "HTTP error"
        case .online:
            return "Online"
        }
    }
}
