import Combine
import Foundation

@MainActor
final class InstanceStore: ObservableObject {
    @Published private(set) var instances: [ProxmoxInstance] = []
    @Published var statuses: [ProxmoxInstance.ID: InstanceStatus] = [:]

    private let defaults: UserDefaults
    private let storageKey: String
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard, storageKey: String = "savedProxmoxInstances") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    func load() {
        guard let data = defaults.data(forKey: storageKey) else {
            instances = []
            statuses = [:]
            return
        }

        do {
            instances = try decoder.decode([ProxmoxInstance].self, from: data)
            pruneStatuses()
        } catch {
            instances = []
            statuses = [:]
        }
    }

    func add(_ instance: ProxmoxInstance) {
        instances.append(instance)
        statuses[instance.id] = .unknown
        save()
    }

    func update(_ instance: ProxmoxInstance) {
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        instances[index] = instance
        statuses[instance.id] = .unknown
        save()
    }

    func updateAPITokenMetadata(for id: ProxmoxInstance.ID, hasToken: Bool, displayName: String?) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        instances[index].hasAPIToken = hasToken
        instances[index].apiDisplayName = displayName
        save()
    }

    func delete(_ instance: ProxmoxInstance) {
        instances.removeAll { $0.id == instance.id }
        statuses.removeValue(forKey: instance.id)
        save()
    }

    func setStatus(_ status: InstanceStatus, for id: ProxmoxInstance.ID) {
        guard statuses[id] != status else { return }
        statuses[id] = status
    }

    @discardableResult
    func save() -> Bool {
        do {
            let data = try encoder.encode(instances)
            defaults.set(data, forKey: storageKey)
            return true
        } catch {
            return false
        }
    }

    private func pruneStatuses() {
        let validIDs = Set(instances.map(\.id))
        statuses = statuses.filter { validIDs.contains($0.key) }
        for instance in instances where statuses[instance.id] == nil {
            statuses[instance.id] = .unknown
        }
    }
}
