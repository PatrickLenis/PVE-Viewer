import Combine
import Foundation
import SwiftUI

@MainActor
final class ProxmoxAppController: ObservableObject {
    let store: InstanceStore
    let tokenStore: AppLocalTokenStore
    let dashboardStore: ProxmoxDashboardStore
    let probeService: StatusProbeService

    @Published var requestedSelectionID: ProxmoxInstance.ID?
    @Published var requestedTokenSettingsID: ProxmoxInstance.ID?

    private var pollingTask: Task<Void, Never>?

    init(
        store: InstanceStore? = nil,
        tokenStore: AppLocalTokenStore = AppLocalTokenStore(),
        probeService: StatusProbeService = StatusProbeService()
    ) {
        self.store = store ?? InstanceStore()
        self.tokenStore = tokenStore
        self.probeService = probeService
        self.dashboardStore = ProxmoxDashboardStore(tokenStore: tokenStore)
    }

    deinit {
        pollingTask?.cancel()
    }

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            while !Task.isCancelled {
                await refreshAll(animated: true)
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refreshAll(animated: Bool) async {
        async let statusRefresh: Void = refreshStatuses(animated: animated)
        async let dashboardRefresh: Void = dashboardStore.refreshAll(store.instances)
        _ = await (statusRefresh, dashboardRefresh)
    }

    func refreshStatuses(animated: Bool) async {
        let instances = store.instances
        await withTaskGroup(of: (ProxmoxInstance.ID, InstanceStatus).self) { group in
            for instance in instances {
                group.addTask {
                    let status = await self.probeService.status(for: instance)
                    return (instance.id, status)
                }
            }

            for await (id, status) in group {
                if animated {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        store.setStatus(status, for: id)
                    }
                } else {
                    store.setStatus(status, for: id)
                }
            }
        }
    }

    func delete(_ instance: ProxmoxInstance) {
        store.delete(instance)
        try? tokenStore.deleteToken(for: instance.id)
        dashboardStore.remove(instanceID: instance.id)
    }

    func focus(_ instance: ProxmoxInstance) {
        requestedSelectionID = instance.id
    }

    func openTokenSettings(for instance: ProxmoxInstance) {
        requestedSelectionID = instance.id
        requestedTokenSettingsID = nil
        requestedTokenSettingsID = instance.id
    }
}
