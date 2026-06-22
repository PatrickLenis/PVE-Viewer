import XCTest
@testable import PVEViewer

final class ProxmoxAPIModelsTests: XCTestCase {
    func testDecodesResourcesEnvelope() throws {
        let json = """
        {
          "data": [
            {
              "type": "qemu",
              "node": "pve",
              "vmid": 100,
              "name": "router",
              "status": "running",
              "cpu": 0.12,
              "mem": 1024,
              "maxmem": 2048,
              "disk": 10,
              "maxdisk": 100
            },
            {
              "type": "lxc",
              "node": "pve",
              "vmid": 101,
              "name": "dns",
              "status": "stopped"
            }
          ]
        }
        """.data(using: .utf8)!

        let resources = try JSONDecoder().decode(ProxmoxAPIEnvelope<[ProxmoxResource]>.self, from: json).data

        XCTAssertEqual(resources.count, 2)
        XCTAssertEqual(resources[0].kind, .qemu)
        XCTAssertEqual(resources[0].name, "router")
        XCTAssertEqual(resources[1].kind, .lxc)
        XCTAssertEqual(resources[1].status, "stopped")
    }

    func testDecodesNodesEnvelope() throws {
        let json = """
        {
          "data": [
            { "node": "pve", "status": "online", "cpu": 0.5, "mem": 2048, "maxmem": 4096 }
          ]
        }
        """.data(using: .utf8)!

        let nodes = try JSONDecoder().decode(ProxmoxAPIEnvelope<[ProxmoxNodeSummary]>.self, from: json).data

        XCTAssertEqual(nodes.first?.node, "pve")
        XCTAssertEqual(nodes.first?.status, "online")
        XCTAssertEqual(nodes.first?.cpu, 0.5)
    }

    func testDecodesNestedNodeStatusMemory() throws {
        let json = """
        {
          "data": {
            "cpu": 0.2,
            "memory": {
              "used": 1024,
              "total": 4096
            }
          }
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(ProxmoxAPIEnvelope<ProxmoxNodeStatus>.self, from: json).data

        XCTAssertEqual(status.cpu, 0.2)
        XCTAssertEqual(status.mem, 1024)
        XCTAssertEqual(status.maxmem, 4096)
    }
}
