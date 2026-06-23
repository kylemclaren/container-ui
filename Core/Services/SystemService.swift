import Foundation

/// System/service management (`container system …`).
struct SystemService: Sendable {
    let cli: ContainerCLI

    init(cli: ContainerCLI) { self.cli = cli }

    // MARK: Argument builders (pure, unit-tested)

    static func statusArguments() -> [String] {
        ["system", "status", "--format", "json"]
    }

    static func dfArguments() -> [String] {
        ["system", "df", "--format", "json"]
    }

    static func versionArguments() -> [String] {
        ["system", "version", "--format", "json"]
    }

    static func startArguments() -> [String] {
        // Pass --enable-kernel-install so the first start doesn't block on an
        // interactive stdin prompt to install the recommended kernel.
        ["system", "start", "--enable-kernel-install"]
    }

    static func stopArguments() -> [String] {
        ["system", "stop"]
    }

    // MARK: Operations

    /// Probes backend status. Unlike most commands, `system status` prints valid
    /// JSON even when the service is down (and exits 1), so we decode stdout
    /// regardless of the exit code.
    func status() async throws -> SystemStatus {
        let result = try await cli.run(Self.statusArguments())
        let data = result.standardOutput
        guard !data.isEmpty else { throw CLIError.classify(result) }
        return try ContainerCLI.decodeJSON(SystemStatus.self, from: data)
    }

    /// Disk usage. Throws `.daemonNotRunning` when the backend is down.
    func diskUsage() async throws -> DiskUsageStats {
        try await cli.decode(DiskUsageStats.self, from: Self.dfArguments())
    }

    /// Version info: 1 element (CLI only) when down, 2 when up.
    func version() async throws -> [VersionInfo] {
        try await cli.decode([VersionInfo].self, from: Self.versionArguments())
    }

    /// Starts the system service, streaming its (human-readable) progress output.
    func start() -> AsyncThrowingStream<StreamLine, Error> {
        cli.stream(Self.startArguments())
    }

    @discardableResult
    func stop() async throws -> String {
        try await cli.text(Self.stopArguments())
    }
}
