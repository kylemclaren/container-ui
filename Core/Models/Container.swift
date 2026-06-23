import Foundation

/// A container as returned by `container list --format json` and
/// `container inspect` (the CLI's `ManagedContainer`). The wire object also
/// carries a top-level `id` equal to `configuration.id`; we derive `id` from
/// the configuration and ignore the duplicate.
struct Container: Codable, Hashable, Identifiable, Sendable {
    var configuration: ContainerConfiguration
    var status: ContainerStatus

    var id: String { configuration.id }

    private enum CodingKeys: String, CodingKey {
        case configuration, status
    }
}

extension Container {
    /// Containers have no separate display name; the id *is* the name.
    var name: String { configuration.id }
    var imageReference: String { configuration.image.reference }
    var state: RuntimeState { status.state }
    var isRunning: Bool { status.state == .running }
    var cpus: Int { configuration.resources.cpus }
    var memoryInBytes: UInt64 { configuration.resources.memoryInBytes }
    var createdAt: Date { configuration.creationDate }
    var startedAt: Date? { status.startedDate }

    /// The first assigned IPv4 address (CIDR form, e.g. `192.168.64.3/24`).
    var primaryIPv4: String? { status.networks.first?.ipv4Address }

    /// IPv4 address without the CIDR suffix, e.g. `192.168.64.3`.
    var primaryIPv4Address: String? {
        primaryIPv4.map { $0.split(separator: "/").first.map(String.init) ?? $0 }
    }

    var platformDisplay: String { configuration.platform.display }
}

/// The static configuration of a container. Only the fields the UI consumes are
/// modeled; unknown keys are ignored by `Codable`.
struct ContainerConfiguration: Codable, Hashable, Sendable {
    var id: String
    var image: ImageDescription
    var platform: OCIPlatform
    var resources: Resources
    var labels: [String: String]
    var networks: [AttachmentConfiguration]
    var initProcess: ProcessConfiguration
    var runtimeHandler: String
    var rosetta: Bool
    var virtualization: Bool
    var ssh: Bool
    var readOnly: Bool
    var publishedPorts: [PublishPort]
    var publishedSockets: [PublishSocket]
    var mounts: [Mount]
    var dns: DNSConfiguration?
    var stopSignal: String?
    var shmSize: UInt64?
    var creationDate: Date
}

/// Runtime status wrapper: `state`, runtime network attachments (with IPs), and
/// the start time (omitted for never-started containers).
struct ContainerStatus: Codable, Hashable, Sendable {
    var state: RuntimeState
    var networks: [Attachment]
    var startedDate: Date?
}

/// The container run state. Decoding is lenient: any unrecognized value maps to
/// `.unknown` so a future backend can't break the UI.
enum RuntimeState: String, Codable, Hashable, Sendable, CaseIterable {
    case unknown
    case stopped
    case running
    case stopping

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RuntimeState(rawValue: raw) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .stopped: return "Stopped"
        case .running: return "Running"
        case .stopping: return "Stopping"
        }
    }
}

/// The image a container was created from.
struct ImageDescription: Codable, Hashable, Sendable {
    var reference: String
    var descriptor: OCIDescriptor
}

/// Compute/memory allocation. Extra keys (`cpuOverhead`) are ignored.
struct Resources: Codable, Hashable, Sendable {
    var cpus: Int
    var memoryInBytes: UInt64
    var storage: UInt64?
}

/// A runtime network attachment, including assigned addresses.
struct Attachment: Codable, Hashable, Sendable {
    var network: String
    var hostname: String
    var ipv4Address: String
    var ipv4Gateway: String
    var ipv6Address: String?
    var macAddress: String?
    var mtu: UInt32?
}

/// A configured network attachment (no runtime IPs).
struct AttachmentConfiguration: Codable, Hashable, Sendable {
    var network: String
    var options: Options?

    struct Options: Codable, Hashable, Sendable {
        var hostname: String?
        var macAddress: String?
        var mtu: UInt32?
    }
}

/// The init process configuration. `supplementalGroups`/`rlimits` are ignored.
struct ProcessConfiguration: Codable, Hashable, Sendable {
    var executable: String
    var arguments: [String]
    var environment: [String]
    var workingDirectory: String
    var terminal: Bool
    var user: ProcessUser

    /// The full command line, e.g. `/bin/sh -c "sleep infinity"`.
    var commandLine: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

/// The process user, encoded as exactly one of two shapes:
/// `{"id":{"uid":0,"gid":0}}` or `{"raw":{"userString":"root"}}`.
struct ProcessUser: Codable, Hashable, Sendable {
    var id: IDUser?
    var raw: RawUser?

    struct IDUser: Codable, Hashable, Sendable {
        var uid: UInt32
        var gid: UInt32
    }

    struct RawUser: Codable, Hashable, Sendable {
        var userString: String
    }

    var display: String {
        if let id { return "\(id.uid):\(id.gid)" }
        if let raw { return raw.userString }
        return "—"
    }
}

/// A published port mapping (host → container).
struct PublishPort: Codable, Hashable, Sendable, Identifiable {
    var hostAddress: String
    var hostPort: UInt16
    var containerPort: UInt16
    var proto: String
    var count: UInt16

    var id: String { "\(hostAddress):\(hostPort)->\(containerPort)/\(proto)" }
    var display: String { "\(hostAddress):\(hostPort) → \(containerPort)/\(proto)" }
}

/// A published unix socket mapping (host ↔ container).
struct PublishSocket: Codable, Hashable, Sendable, Identifiable {
    var hostPath: String
    var containerPath: String
    var permissions: Int?

    var id: String { "\(hostPath)->\(containerPath)" }
}

/// A filesystem mount. The complex `type` discriminator is ignored; the UI only
/// shows source → destination and options.
struct Mount: Codable, Hashable, Sendable, Identifiable {
    var source: String
    var destination: String
    var options: [String]

    var id: String { "\(source)->\(destination)" }

    private enum CodingKeys: String, CodingKey {
        case source, destination, options
    }
}

/// DNS configuration for a container.
struct DNSConfiguration: Codable, Hashable, Sendable {
    var nameservers: [String]
    var domain: String?
    var searchDomains: [String]
    var options: [String]
}
