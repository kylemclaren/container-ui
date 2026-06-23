import Foundation

/// Output of `container system status --format json` (the CLI's
/// `PrintableStatus`). When the backend is down the command still prints valid
/// JSON (with empty string fields) and exits 1, so this always decodes.
struct SystemStatus: Codable, Hashable, Sendable {
    /// One of `running`, `not running`, `unregistered`.
    var status: String
    var appRoot: String
    var installRoot: String
    /// Omitted from JSON when nil (always absent in the down cases).
    var logRoot: String?
    var apiServerVersion: String
    var apiServerCommit: String
    var apiServerBuild: String
    var apiServerAppName: String

    enum State: String, Sendable {
        case running
        case notRunning
        case unregistered
        case unknown
    }

    var state: State {
        switch status {
        case "running": return .running
        case "not running": return .notRunning
        case "unregistered": return .unregistered
        default: return .unknown
        }
    }

    var isRunning: Bool { state == .running }
}

/// Output of `container system df --format json` (the CLI's `DiskUsageStats`).
struct DiskUsageStats: Codable, Hashable, Sendable {
    var images: ResourceUsage
    var containers: ResourceUsage
    var volumes: ResourceUsage
}

/// Per-resource-type disk usage. `sizeInBytes`/`reclaimable` are `UInt64` and
/// may exceed 2^53.
struct ResourceUsage: Codable, Hashable, Sendable {
    var total: Int
    var active: Int
    var sizeInBytes: UInt64
    var reclaimable: UInt64
}

/// One element of `container system version --format json`. The array has one
/// element (the CLI) when the backend is down, two when it's up.
struct VersionInfo: Codable, Hashable, Sendable, Identifiable {
    var appName: String
    var version: String
    var buildType: String
    var commit: String

    var id: String { appName }
}
