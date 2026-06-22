import XCTest
@testable import PVEViewer

final class ProxmoxAPIServiceTests: XCTestCase {
    func testRequestUsesPVEAPITokenHeaderAndAPIPath() throws {
        let token = ProxmoxAPIToken(tokenID: "fixture@pve!viewer", secret: "fixture-token-value")
        let request = try ProxmoxAPIService.makeRequest(
            baseURL: try XCTUnwrap(URL(string: "https://pve.local:8006")),
            path: "cluster/resources",
            query: ["type": "vm"],
            method: "GET",
            token: token,
            timeout: 12
        )

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 12)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "PVEAPIToken=fixture@pve!viewer=fixture-token-value")
        XCTAssertEqual(request.url?.absoluteString, "https://pve.local:8006/api2/json/cluster/resources?type=vm")
    }

    func testControlPathsForQEMUAndLXC() {
        let vm = ProxmoxResource(kind: .qemu, node: "pve", vmid: 100, name: "router")
        let lxc = ProxmoxResource(kind: .lxc, node: "pve", vmid: 101, name: "dns")
        let storage = ProxmoxResource(kind: .storage, node: "pve", name: "local")

        XCTAssertEqual(ProxmoxAPIService.controlPath(for: vm, action: .start), "nodes/pve/qemu/100/status/start")
        XCTAssertEqual(ProxmoxAPIService.controlPath(for: lxc, action: .reboot), "nodes/pve/lxc/101/status/reboot")
        XCTAssertNil(ProxmoxAPIService.controlPath(for: storage, action: .stop))
    }

    func testClusterMetricAggregation() {
        let metrics = ProxmoxAPIService.clusterMetrics(
            nodes: [
                ProxmoxNodeStatus(cpu: 0.25, mem: 2, maxmem: 4),
                ProxmoxNodeStatus(cpu: 0.75, mem: 1, maxmem: 4)
            ],
            storage: [
                ProxmoxResource(kind: .storage, node: "pve", name: "local", disk: 20, maxdisk: 100),
                ProxmoxResource(kind: .storage, node: "pve", name: "fast", disk: 30, maxdisk: 100)
            ]
        )

        XCTAssertEqual(metrics.cpuUsage, 0.5)
        XCTAssertEqual(metrics.memoryUsage, 0.375)
        XCTAssertEqual(metrics.storageUsage, 0.25)
    }

    func testMetricNodeFallbackUsesSummariesWhenStatusesHaveNoMemory() {
        let nodes = ProxmoxAPIService.preferredMetricNodes(
            statuses: [ProxmoxNodeStatus(cpu: 0.4, mem: nil, maxmem: nil)],
            summaries: [ProxmoxNodeStatus(cpu: 0.5, mem: 2, maxmem: 8)]
        )

        XCTAssertEqual(nodes, [ProxmoxNodeStatus(cpu: 0.5, mem: 2, maxmem: 8)])
    }
}
