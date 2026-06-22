import Foundation

protocol APITokenStoring {
    func saveToken(_ token: ProxmoxAPIToken, for instanceID: ProxmoxInstance.ID) throws
    func loadToken(for instanceID: ProxmoxInstance.ID) throws -> ProxmoxAPIToken?
    func deleteToken(for instanceID: ProxmoxInstance.ID) throws
}

enum AppLocalTokenStoreError: LocalizedError, Equatable {
    case applicationSupportUnavailable
    case encodeFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "The app token storage folder could not be found."
        case .encodeFailed:
            return "The API token could not be saved."
        case .decodeFailed:
            return "The saved API token could not be read."
        }
    }
}

final class AppLocalTokenStore: APITokenStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL(fileManager: fileManager)
        }
    }

    func saveToken(_ token: ProxmoxAPIToken, for instanceID: ProxmoxInstance.ID) throws {
        var tokens = try loadAllTokens()
        tokens[instanceID.uuidString] = token
        try saveAllTokens(tokens)
    }

    func loadToken(for instanceID: ProxmoxInstance.ID) throws -> ProxmoxAPIToken? {
        try loadAllTokens()[instanceID.uuidString]
    }

    func deleteToken(for instanceID: ProxmoxInstance.ID) throws {
        var tokens = try loadAllTokens()
        tokens.removeValue(forKey: instanceID.uuidString)
        try saveAllTokens(tokens)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        if let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return applicationSupportURL
                .appendingPathComponent("PVE Viewer", isDirectory: true)
                .appendingPathComponent("APITokens.json")
        }

        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PVE Viewer", isDirectory: true)
            .appendingPathComponent("APITokens.json")
    }

    private func loadAllTokens() throws -> [String: ProxmoxAPIToken] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([String: ProxmoxAPIToken].self, from: data)
        } catch {
            throw AppLocalTokenStoreError.decodeFailed
        }
    }

    private func saveAllTokens(_ tokens: [String: ProxmoxAPIToken]) throws {
        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(tokens)
            try data.write(to: fileURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            throw AppLocalTokenStoreError.encodeFailed
        }
    }
}
