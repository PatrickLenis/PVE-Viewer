import XCTest
@testable import PVEViewer

@MainActor
final class InstanceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "InstanceStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testLoadSaveAddEditDelete() throws {
        let store = InstanceStore(defaults: defaults, storageKey: "instances")
        let original = ProxmoxInstance(name: "Lab", url: try XCTUnwrap(URL(string: "https://pve:8006")), allowSelfSignedHTTPS: false)

        store.add(original)
        XCTAssertEqual(store.instances, [original])

        let reloaded = InstanceStore(defaults: defaults, storageKey: "instances")
        XCTAssertEqual(reloaded.instances, [original])

        let updated = ProxmoxInstance(id: original.id, name: "Lab Updated", url: try XCTUnwrap(URL(string: "https://pve.local:8006")), allowSelfSignedHTTPS: true)
        reloaded.update(updated)
        XCTAssertEqual(reloaded.instances, [updated])

        let finalReload = InstanceStore(defaults: defaults, storageKey: "instances")
        XCTAssertEqual(finalReload.instances, [updated])

        finalReload.delete(updated)
        XCTAssertTrue(finalReload.instances.isEmpty)
        XCTAssertTrue(InstanceStore(defaults: defaults, storageKey: "instances").instances.isEmpty)
    }

    func testAPITokenMetadataDoesNotPersistSecret() throws {
        let store = InstanceStore(defaults: defaults, storageKey: "instances")
        let instance = ProxmoxInstance(name: "Lab", url: try XCTUnwrap(URL(string: "https://pve:8006")))

        store.add(instance)
        store.updateAPITokenMetadata(for: instance.id, hasToken: true, displayName: "monitor@pve!viewer")

        let data = try XCTUnwrap(defaults.data(forKey: "instances"))
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("monitor@pve!viewer"))
        XCTAssertFalse(json.contains("secret"))

        let reloaded = InstanceStore(defaults: defaults, storageKey: "instances")
        XCTAssertEqual(reloaded.instances.first?.hasAPIToken, true)
        XCTAssertEqual(reloaded.instances.first?.apiDisplayName, "monitor@pve!viewer")
    }
}
