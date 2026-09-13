import Foundation

/// A container machine as returned by `container machine list --format json`
/// (the CLI's `PrintableMachine`). `ipAddress` and `diskSize` are omitted when
/// unknown — a stopped machine has no address.
///
/// Machines are long-lived Linux environments (the image's init system boots,
/// the host user and home directory are mapped in). The CLI hides a machine's
/// backing container from `container list`, so the two screens never overlap.
struct ContainerMachine: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var status: RuntimeState
    var isDefault: Bool
    var ipAddress: String?
    var cpus: Int
    var memory: UInt64
    var diskSize: UInt64?
    var createdDate: Date?

    private enum CodingKeys: String, CodingKey {
        case id, status, ipAddress, cpus, memory, diskSize, createdDate
        case isDefault = "default"
    }
}

extension ContainerMachine {
    /// Machines have no separate display name; the id *is* the name.
    var name: String { id }
    var state: RuntimeState { status }
    var isRunning: Bool { status == .running }
}

/// How the host user's home directory is exposed inside a machine. The CLI
/// value for "not mounted" is `none`; the case is named `notMounted` because
/// `.none` on an optional of this type would resolve to `Optional.none`.
enum MachineHomeMount: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case rw = "rw"
    case ro = "ro"
    case notMounted = "none"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rw: return "Read & write"
        case .ro: return "Read only"
        case .notMounted: return "Not mounted"
        }
    }
}

/// The host account provisioned inside a machine on first boot.
struct MachineUserSetup: Codable, Hashable, Sendable {
    var username: String
    var uid: UInt32
    var gid: UInt32
}

/// One element of `container machine inspect` (the CLI's `InspectOutput`).
/// `containerId` is present only while the machine is running; it names the
/// backing container, which `container stats` accepts for live metrics.
struct MachineDetail: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var image: ImageDescription
    var platform: OCIPlatform
    var userSetup: MachineUserSetup
    var status: RuntimeState
    var startedDate: Date?
    var createdDate: Date?
    var containerId: String?
    var cpus: Int
    var memory: UInt64
    var homeMount: MachineHomeMount
    var diskSize: UInt64?
    var ipAddress: String?
}

extension MachineDetail {
    var isRunning: Bool { status == .running }
    var imageReference: String { image.reference }
}
