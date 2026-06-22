import Combine
import Foundation

enum ProxmoxDashboardLoadState: Equatable {
    case idle
    case loading
    case loaded(ProxmoxDashboardSnapshot)
    case failed(String)

    var snapshot: ProxmoxDashboardSnapshot? {
        if case .loaded(let snapshot) = self {
            return snapshot
        }
        return nil
    }

    var errorMessage: String? {
        if case .failed(let message) = self {
            return message
        }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

@MainActor
final class ProxmoxDashboardStore: ObservableObject {
    @Published private(set) var states: [ProxmoxInstance.ID: ProxmoxDashboardLoadState] = [:]
    @Published private(set) var actionInProgressIDs: Set<String> = []

    private let tokenStore: APITokenStoring
    private let apiService: ProxmoxAPIService
    private var pollingTask: Task<Void, Never>?

    init(tokenStore: APITokenStoring, apiService: ProxmoxAPIService = ProxmoxAPIService()) {
        self.tokenStore = tokenStore
        self.apiService = apiService
    }

    deinit {
        pollingTask?.cancel()
    }

    func state(for id: ProxmoxInstance.ID) -> ProxmoxDashboardLoadState {
        states[id] ?? .idle
    }

    func startPolling(instancesProvider: @MainActor @escaping () -> [ProxmoxInstance]) {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            while !Task.isCancelled {
                await refreshAll(instancesProvider())
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refreshAll(_ instances: [ProxmoxInstance]) async {
        pruneStates(validIDs: Set(instances.map(\.id)))
        await withTaskGroup(of: Void.self) { group in
            for instance in instances where instance.hasAPIToken {
                group.addTask { await self.refresh(instance) }
            }
        }
    }

    func refresh(_ instance: ProxmoxInstance) async {
        guard instance.hasAPIToken else {
            states.removeValue(forKey: instance.id)
            return
        }

        if states[instance.id]?.snapshot == nil, states[instance.id] != .loading {
            states[instance.id] = .loading
        }

        do {
            guard let token = try tokenStore.loadToken(for: instance.id) else {
                states[instance.id] = .failed(ProxmoxAPIError.missingToken.localizedDescription)
                return
            }
            let snapshot = try await apiService.fetchSnapshot(for: instance, token: token)
            let loadedState = ProxmoxDashboardLoadState.loaded(snapshot)
            if states[instance.id] != loadedState {
                states[instance.id] = loadedState
            }
        } catch {
            states[instance.id] = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func perform(_ action: ProxmoxResourceAction, on resource: ProxmoxResource, instance: ProxmoxInstance) async {
        let actionID = actionIdentifier(action: action, resource: resource)
        actionInProgressIDs.insert(actionID)
        defer { actionInProgressIDs.remove(actionID) }

        do {
            guard let token = try tokenStore.loadToken(for: instance.id) else {
                states[instance.id] = .failed(ProxmoxAPIError.missingToken.localizedDescription)
                return
            }
            try await apiService.perform(action, resource: resource, instance: instance, token: token)
            await refresh(instance)
        } catch {
            states[instance.id] = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func remove(instanceID: ProxmoxInstance.ID) {
        states.removeValue(forKey: instanceID)
    }

    func isActionInProgress(_ action: ProxmoxResourceAction, resource: ProxmoxResource) -> Bool {
        actionInProgressIDs.contains(actionIdentifier(action: action, resource: resource))
    }

    private func pruneStates(validIDs: Set<ProxmoxInstance.ID>) {
        let prunedStates = states.filter { validIDs.contains($0.key) }
        if prunedStates != states {
            states = prunedStates
        }
    }

    private func actionIdentifier(action: ProxmoxResourceAction, resource: ProxmoxResource) -> String {
        "\(action.rawValue)-\(resource.id)"
    }
}
