import Foundation

struct ProxmoxAPIToken: Codable, Equatable {
    var tokenID: String
    var secret: String
}

struct ProxmoxDashboardSnapshot: Equatable {
    var metrics: ProxmoxClusterMetrics
    var nodes: [ProxmoxNodeSummary]
    var resources: [ProxmoxResource]
    var refreshedAt: Date
}

struct ProxmoxClusterMetrics: Equatable {
    var cpuUsage: Double?
    var memoryUsage: Double?
    var storageUsage: Double?
}

struct ProxmoxNodeSummary: Decodable, Equatable, Identifiable {
    var id: String { node }
    var node: String
    var status: String?
    var cpu: Double?
    var mem: Double?
    var maxmem: Double?
}

struct ProxmoxNodeStatus: Decodable, Equatable {
    var cpu: Double?
    var mem: Double?
    var maxmem: Double?

    private enum CodingKeys: String, CodingKey {
        case cpu
        case mem
        case maxmem
        case memory
    }

    private enum MemoryKeys: String, CodingKey {
        case used
        case total
    }

    init(cpu: Double?, mem: Double?, maxmem: Double?) {
        self.cpu = cpu
        self.mem = mem
        self.maxmem = maxmem
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cpu = try container.decodeIfPresent(Double.self, forKey: .cpu)
        mem = try container.decodeIfPresent(Double.self, forKey: .mem)
        maxmem = try container.decodeIfPresent(Double.self, forKey: .maxmem)

        if let memory = try? container.nestedContainer(keyedBy: MemoryKeys.self, forKey: .memory) {
            if mem == nil {
                mem = try memory.decodeIfPresent(Double.self, forKey: .used)
            }
            if maxmem == nil {
                maxmem = try memory.decodeIfPresent(Double.self, forKey: .total)
            }
        }
    }
}

struct ProxmoxResource: Decodable, Equatable, Identifiable {
    enum Kind: String, Decodable {
        case qemu
        case lxc
        case storage
        case other

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = Kind(rawValue: rawValue) ?? .other
        }

        var apiPathComponent: String? {
            switch self {
            case .qemu:
                return "qemu"
            case .lxc:
                return "lxc"
            case .storage, .other:
                return nil
            }
        }
    }

    var id: String {
        let identifier = vmid.map(String.init) ?? storage ?? name
        return "\(kind.rawValue)-\(node)-\(identifier)"
    }
    var kind: Kind
    var node: String
    var vmid: Int?
    var name: String
    var status: String?
    var cpu: Double?
    var mem: Double?
    var maxmem: Double?
    var disk: Double?
    var maxdisk: Double?
    var storage: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case node
        case vmid
        case name
        case status
        case cpu
        case mem
        case maxmem
        case disk
        case maxdisk
        case storage
    }

    init(
        kind: Kind,
        node: String,
        vmid: Int? = nil,
        name: String,
        status: String? = nil,
        cpu: Double? = nil,
        mem: Double? = nil,
        maxmem: Double? = nil,
        disk: Double? = nil,
        maxdisk: Double? = nil,
        storage: String? = nil
    ) {
        self.kind = kind
        self.node = node
        self.vmid = vmid
        self.name = name
        self.status = status
        self.cpu = cpu
        self.mem = mem
        self.maxmem = maxmem
        self.disk = disk
        self.maxdisk = maxdisk
        self.storage = storage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(Kind.self, forKey: .type) ?? .other
        node = try container.decodeIfPresent(String.self, forKey: .node) ?? ""
        vmid = try container.decodeIfPresent(Int.self, forKey: .vmid)
        storage = try container.decodeIfPresent(String.self, forKey: .storage)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? storage
            ?? vmid.map(String.init)
            ?? "Unknown"
        status = try container.decodeIfPresent(String.self, forKey: .status)
        cpu = try container.decodeIfPresent(Double.self, forKey: .cpu)
        mem = try container.decodeIfPresent(Double.self, forKey: .mem)
        maxmem = try container.decodeIfPresent(Double.self, forKey: .maxmem)
        disk = try container.decodeIfPresent(Double.self, forKey: .disk)
        maxdisk = try container.decodeIfPresent(Double.self, forKey: .maxdisk)
    }
}

struct ProxmoxAPIEnvelope<T: Decodable>: Decodable {
    var data: T
}
