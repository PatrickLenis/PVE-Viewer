import Foundation
import Security

enum ProxmoxResourceAction: String, CaseIterable, Equatable {
    case start
    case stop
    case reboot

    var title: String {
        switch self {
        case .start:
            return "Start"
        case .stop:
            return "Stop"
        case .reboot:
            return "Restart"
        }
    }

    var systemImage: String {
        switch self {
        case .start:
            return "play.fill"
        case .stop:
            return "stop.fill"
        case .reboot:
            return "arrow.clockwise"
        }
    }
}

enum ProxmoxAPIError: LocalizedError, Equatable {
    case missingToken
    case unsupportedResource
    case invalidEndpoint
    case httpStatus(Int)
    case emptyResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No API token is configured for this instance."
        case .unsupportedResource:
            return "This action is only available for VMs and LXC containers."
        case .invalidEndpoint:
            return "The Proxmox API endpoint could not be built."
        case .httpStatus(let status):
            if status == 401 || status == 403 {
                return "The API token was rejected. Check token permissions in Proxmox."
            }
            return "The Proxmox API returned HTTP \(status)."
        case .emptyResponse:
            return "The Proxmox API returned an empty response."
        case .transport(let message):
            return message
        }
    }
}

struct ProxmoxAPIService {
    var timeout: TimeInterval = 10

    func fetchSnapshot(for instance: ProxmoxInstance, token: ProxmoxAPIToken) async throws -> ProxmoxDashboardSnapshot {
        async let nodeList: [ProxmoxNodeSummary] = get([ProxmoxNodeSummary].self, path: "nodes", instance: instance, token: token)
        async let vmList: [ProxmoxResource] = get([ProxmoxResource].self, path: "cluster/resources", query: ["type": "vm"], instance: instance, token: token)
        async let storageList: [ProxmoxResource] = get([ProxmoxResource].self, path: "cluster/resources", query: ["type": "storage"], instance: instance, token: token)

        let nodes = try await nodeList
        let resources = try await vmList
            .filter { $0.kind == .qemu || $0.kind == .lxc }
            .sorted { lhs, rhs in
                if lhs.node != rhs.node { return lhs.node < rhs.node }
                return (lhs.vmid ?? 0) < (rhs.vmid ?? 0)
            }
        let storage = try await storageList

        let nodeStatuses = await fetchNodeStatuses(nodes: nodes, instance: instance, token: token)
        let summaryNodes = nodes.map { ProxmoxNodeStatus(cpu: $0.cpu, mem: $0.mem, maxmem: $0.maxmem) }
        let metricNodes = Self.preferredMetricNodes(statuses: nodeStatuses, summaries: summaryNodes)

        return ProxmoxDashboardSnapshot(
            metrics: Self.clusterMetrics(nodes: metricNodes, storage: storage),
            nodes: nodes,
            resources: resources,
            refreshedAt: Date()
        )
    }

    func perform(_ action: ProxmoxResourceAction, resource: ProxmoxResource, instance: ProxmoxInstance, token: ProxmoxAPIToken) async throws {
        guard let path = Self.controlPath(for: resource, action: action) else {
            throw ProxmoxAPIError.unsupportedResource
        }
        _ = try await request(path: path, method: "POST", instance: instance, token: token)
    }

    func get<T: Decodable>(
        _ type: T.Type,
        path: String,
        query: [String: String] = [:],
        instance: ProxmoxInstance,
        token: ProxmoxAPIToken
    ) async throws -> T {
        let data = try await request(path: path, query: query, method: "GET", instance: instance, token: token)
        guard !data.isEmpty else { throw ProxmoxAPIError.emptyResponse }
        return try JSONDecoder().decode(ProxmoxAPIEnvelope<T>.self, from: data).data
    }

    static func makeRequest(
        baseURL: URL,
        path: String,
        query: [String: String] = [:],
        method: String,
        token: ProxmoxAPIToken,
        timeout: TimeInterval
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ProxmoxAPIError.invalidEndpoint
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let apiPath = ["api2/json", path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.path = "/" + [basePath, apiPath].filter { !$0.isEmpty }.joined(separator: "/")
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
                .sorted { $0.name < $1.name }
        }

        guard let url = components.url else {
            throw ProxmoxAPIError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("PVEAPIToken=\(token.tokenID)=\(token.secret)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func controlPath(for resource: ProxmoxResource, action: ProxmoxResourceAction) -> String? {
        guard let type = resource.kind.apiPathComponent, let vmid = resource.vmid else {
            return nil
        }
        return "nodes/\(resource.node)/\(type)/\(vmid)/status/\(action.rawValue)"
    }

    static func clusterMetrics(nodes: [ProxmoxNodeStatus], storage: [ProxmoxResource]) -> ProxmoxClusterMetrics {
        let cpuValues = nodes.compactMap(\.cpu)
        let cpuUsage = cpuValues.isEmpty ? nil : cpuValues.reduce(0, +) / Double(cpuValues.count)

        let usedMemory = nodes.compactMap(\.mem).reduce(0, +)
        let maxMemory = nodes.compactMap(\.maxmem).reduce(0, +)
        let memoryUsage = maxMemory > 0 ? usedMemory / maxMemory : nil

        let usedStorage = storage.compactMap(\.disk).reduce(0, +)
        let maxStorage = storage.compactMap(\.maxdisk).reduce(0, +)
        let storageUsage = maxStorage > 0 ? usedStorage / maxStorage : nil

        return ProxmoxClusterMetrics(cpuUsage: cpuUsage, memoryUsage: memoryUsage, storageUsage: storageUsage)
    }

    static func preferredMetricNodes(statuses: [ProxmoxNodeStatus], summaries: [ProxmoxNodeStatus]) -> [ProxmoxNodeStatus] {
        guard !statuses.isEmpty else { return summaries }

        let hasStatusMemory = statuses.contains { ($0.maxmem ?? 0) > 0 }
        if hasStatusMemory {
            return statuses
        }

        return summaries.isEmpty ? statuses : summaries
    }

    private func request(
        path: String,
        query: [String: String] = [:],
        method: String,
        instance: ProxmoxInstance,
        token: ProxmoxAPIToken
    ) async throws -> Data {
        let request = try Self.makeRequest(
            baseURL: instance.url,
            path: path,
            query: query,
            method: method,
            token: token,
            timeout: timeout
        )
        let delegate = ProxmoxAPISessionDelegate(instance: instance)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw ProxmoxAPIError.httpStatus(httpResponse.statusCode)
            }
            return data
        } catch let apiError as ProxmoxAPIError {
            throw apiError
        } catch {
            throw ProxmoxAPIError.transport((error as NSError).localizedDescription)
        }
    }

    private func fetchNodeStatuses(
        nodes: [ProxmoxNodeSummary],
        instance: ProxmoxInstance,
        token: ProxmoxAPIToken
    ) async -> [ProxmoxNodeStatus] {
        await withTaskGroup(of: ProxmoxNodeStatus?.self) { group in
            for node in nodes {
                group.addTask {
                    try? await get(
                        ProxmoxNodeStatus.self,
                        path: "nodes/\(node.node)/status",
                        instance: instance,
                        token: token
                    )
                }
            }

            var statuses: [ProxmoxNodeStatus] = []
            for await status in group {
                if let status {
                    statuses.append(status)
                }
            }
            return statuses
        }
    }
}

private final class ProxmoxAPISessionDelegate: NSObject, URLSessionDelegate {
    private let instance: ProxmoxInstance

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

        return (.useCredential, URLCredential(trust: trust))
    }
}
