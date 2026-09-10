import Foundation
import Testing

@Suite("System status compatibility")
struct SystemStatusCompatibilityTests {
    // Shape verified against apple/container tag 1.4.1:
    // Sources/ContainerCommands/System/SystemStatus.swift (StatusPayload).
    static let running141 = """
    {
      "status": "running",
      "client": {"version":"1.4.1","build":"release","commit":"client-sha","appName":"container"},
      "server": {"version":"1.4.1","build":"release","commit":"server-sha","appName":"container-apiserver"},
      "host": {"architecture":"arm64","operatingSystem":"macOS 26","cpus":8},
      "paths": {"appRoot":"/Users/test/Library/Application Support/com.apple.container","installRoot":"/usr/local","logRoot":"/Users/test/Library/Logs/com.apple.container"},
      "resources": {"containersTotal":3,"containersRunning":2,"images":5}
    }
    """

    @Test func running141IsDetectedAndPreservesServerMetadata() async throws {
        let mock = MockCommandRunner(stdout: Self.running141)
        let status = try await SystemService(cli: .mock(mock)).status()
        #expect(status.isRunning)
        #expect(status.apiServerVersion == "1.4.1")
        #expect(status.apiServerCommit == "server-sha")
        #expect(status.apiServerBuild == "release")
        #expect(status.apiServerAppName == "container-apiserver")
        #expect(status.installRoot == "/usr/local")
        #expect(status.appRoot == "/Users/test/Library/Application Support/com.apple.container")
        #expect(status.logRoot == "/Users/test/Library/Logs/com.apple.container")
        #expect(mock.lastArguments == ["system", "status", "--format", "json"])
    }

    @Test(arguments: ["unregistered", "not running"])
    func minimalDownResponseDecodesDespiteExitOne(_ state: String) async throws {
        let mock = MockCommandRunner(stdout: "{\"status\":\"\(state)\"}", exitCode: 1)
        let status = try await SystemService(cli: .mock(mock)).status()
        #expect(!status.isRunning)
        #expect(status.state == (state == "unregistered" ? .unregistered : .notRunning))
        #expect(status.apiServerVersion.isEmpty)
        #expect(status.installRoot.isEmpty)
        #expect(status.logRoot == nil)
    }

    @Test func optionalMetadataAndLogRootCanBeAbsent() async throws {
        let json = """
        {"status":"running","paths":{"appRoot":"/app","installRoot":"/usr/local"}}
        """
        let status = try await SystemService(cli: .mock(MockCommandRunner(stdout: json))).status()
        #expect(status.isRunning)
        #expect(status.appRoot == "/app")
        #expect(status.logRoot == nil)
    }

    @Test(arguments: ["{}", "{\"status\":42}", "{\"status\":\"running\",\"server\":[]}"])
    func malformedPayloadStillFails(_ json: String) async {
        let service = SystemService(cli: .mock(MockCommandRunner(stdout: json)))
        await #expect(throws: CLIError.self) { try await service.status() }
    }

    @Test func legacyRunningAndDownResponsesRemainSupported() async throws {
        let running = try await SystemService(cli: .mock(MockCommandRunner(stdout: Fixtures.systemStatusRunning))).status()
        #expect(running.isRunning)
        #expect(running.apiServerVersion == "0.4.1")
        let down = try await SystemService(cli: .mock(MockCommandRunner(stdout: Fixtures.systemStatusUnregistered, exitCode: 1))).status()
        #expect(down.state == .unregistered)
    }
}
