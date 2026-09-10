import Foundation

/// Output of `container system status --format json` (the CLI's
/// legacy `PrintableStatus` or 1.4.1+ `StatusPayload`). Metadata moved into
/// `server` and `paths` in 1.4.1; down responses now contain only `status`.
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

    private enum CodingKeys: String, CodingKey {
        case status, appRoot, installRoot, logRoot
        case apiServerVersion, apiServerCommit, apiServerBuild, apiServerAppName
    }

    private enum EnvelopeKeys: String, CodingKey { case server, paths }

    private struct Server: Decodable {
        let version: String
        let commit: String
        let build: String
        let appName: String
    }

    private struct Paths: Decodable {
        let appRoot: String
        let installRoot: String
        let logRoot: String?
    }

    init(from decoder: Decoder) throws {
        let legacy = try decoder.container(keyedBy: CodingKeys.self)
        let envelope = try decoder.container(keyedBy: EnvelopeKeys.self)
        // Status is authoritative and required; absent metadata must not make a
        // stopped/unregistered service look like a broken CLI installation.
        status = try legacy.decode(String.self, forKey: .status)
        let server = try envelope.decodeIfPresent(Server.self, forKey: .server)
        let paths = try envelope.decodeIfPresent(Paths.self, forKey: .paths)
        appRoot = try paths?.appRoot ?? legacy.decodeIfPresent(String.self, forKey: .appRoot) ?? ""
        installRoot = try paths?.installRoot ?? legacy.decodeIfPresent(String.self, forKey: .installRoot) ?? ""
        logRoot = try paths?.logRoot ?? legacy.decodeIfPresent(String.self, forKey: .logRoot)
        apiServerVersion = try server?.version ?? legacy.decodeIfPresent(String.self, forKey: .apiServerVersion) ?? ""
        apiServerCommit = try server?.commit ?? legacy.decodeIfPresent(String.self, forKey: .apiServerCommit) ?? ""
        apiServerBuild = try server?.build ?? legacy.decodeIfPresent(String.self, forKey: .apiServerBuild) ?? ""
        apiServerAppName = try server?.appName ?? legacy.decodeIfPresent(String.self, forKey: .apiServerAppName) ?? ""
    }

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
