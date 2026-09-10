import Foundation
import Testing

@Suite("Compose lifecycle")
struct ComposeServiceTests {
    private func result(_ text: String, code: Int32 = 0) -> CommandResult {
        .init(standardOutput: Data(text.utf8), standardError: Data(), exitCode: code)
    }

    private func fixture() throws -> (ComposeProject, ComposeManifest) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("compose.yaml")
        try "name: test\nservices: {web: {image: nginx}}".write(to: file, atomically: true, encoding: .utf8)
        let project = ComposeProject(fileURL: file)
        return (project, try ComposeManifest.read(project))
    }

    @Test @MainActor func startStreamsAndVerifiesCreatedContainers() async throws {
        let (project, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: project.directory) }
        let owned = try ComposeTests.container(name: "test-web", project: "test", service: "web")
        let encoded = try JSONEncoder.compose.encode([owned])
        let backend = MockCommandRunner(stdout: "container-compose version 1.1.0")
        backend.streamLines = [.standardOutput("Starting web"), .standardError("progress")]
        let runtime = MockCommandRunner(stdout: String(decoding: encoded, as: UTF8.self))
        let service = ComposeService(executableURL: URL(fileURLWithPath: "/compose"), containerCLI: .mock(runtime), runner: backend)
        var lines: [String] = []
        try await service.start(project, expected: manifest, rebuild: false) { lines.append($0) }
        #expect(lines == ["Starting web", "progress"])
        #expect(backend.invocations.count == 2)
        #expect(runtime.invocations.count == 2)
    }

    @Test @MainActor func zeroExitWithoutContainersIsFailure() async throws {
        let (project, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: project.directory) }
        let backend = MockCommandRunner(stdout: "container-compose version 1.1.0")
        let service = ComposeService(executableURL: URL(fileURLWithPath: "/compose"), containerCLI: .mock(MockCommandRunner(stdout: "[]")), runner: backend)
        await #expect(throws: ComposeError.self) { try await service.start(project, expected: manifest, rebuild: false) { _ in } }
    }

    @Test @MainActor func changedCommandBlocksBeforeMutation() async throws {
        let (project, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: project.directory) }
        try "name: test\nservices: {web: {image: nginx, command: [false]}}".write(to: project.fileURL, atomically: true, encoding: .utf8)
        let backend = MockCommandRunner(stdout: "container-compose version 1.1.0")
        let runtime = MockCommandRunner(stdout: "[]")
        let service = ComposeService(executableURL: URL(fileURLWithPath: "/compose"), containerCLI: .mock(runtime), runner: backend)
        await #expect(throws: ComposeError.self) { try await service.start(project, expected: manifest, rebuild: false) { _ in } }
        #expect(backend.invocations.map(\.arguments) == [["--version"]])
        #expect(runtime.invocations.isEmpty)
    }

    @Test @MainActor func streamFailurePropagates() async throws {
        let (project, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: project.directory) }
        let backend = MockCommandRunner(stdout: "container-compose version 1.1.0")
        backend.streamError = CLIError.commandFailed(code: 1, stderr: "build failed")
        let service = ComposeService(executableURL: URL(fileURLWithPath: "/compose"), containerCLI: .mock(MockCommandRunner(stdout: "[]")), runner: backend)
        await #expect(throws: CLIError.self) { try await service.start(project, expected: manifest, rebuild: false) { _ in } }
    }

    @Test @MainActor func stopOnlyOwnedRunningContainersAndRetainsResources() async throws {
        let (project, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: project.directory) }
        let owned = try ComposeTests.container(name: "test-web", project: "test", service: "web")
        let other = try ComposeTests.container(name: "test-other", project: nil, service: nil)
        let alreadyStopped = try ComposeTests.container(name: "test-debug", project: "test", service: "debug", running: false)
        let state = StopState(containers: [owned, other, alreadyStopped])
        let runtime = MockCommandRunner { invocation in state.respond(invocation) }
        let backend = MockCommandRunner(exitCode: 1)
        let service = ComposeService(executableURL: URL(fileURLWithPath: "/missing-compose"), containerCLI: .mock(runtime), runner: backend)
        try await service.stop(manifest: manifest) { _ in }
        #expect(runtime.invocations.map(\.arguments) == [["list", "--all", "--format", "json"], ["stop", "test-web"], ["list", "--all", "--format", "json"]])
        #expect(backend.invocations.isEmpty)
    }

    @Test @MainActor func stopFailureIsVisible() async throws {
        let (project, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: project.directory) }
        let owned = try ComposeTests.container(name: "test-web", project: "test", service: "web")
        let json = try JSONEncoder.compose.encode([owned])
        let runtime = MockCommandRunner { invocation in
            if invocation.arguments.first == "stop" { return .init(standardOutput: Data(), standardError: Data("stop failed".utf8), exitCode: 1) }
            return .init(standardOutput: json, standardError: Data(), exitCode: 0)
        }
        let service = ComposeService(executableURL: URL(fileURLWithPath: "/compose"), containerCLI: .mock(runtime))
        await #expect(throws: CLIError.self) { try await service.stop(manifest: manifest) { _ in } }
    }
}

private extension JSONEncoder {
    static var compose: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }
}

private final class StopState: @unchecked Sendable {
    private let lock = NSLock()
    private var containers: [Container]
    init(containers: [Container]) { self.containers = containers }
    func respond(_ invocation: CommandInvocation) -> CommandResult {
        lock.lock(); defer { lock.unlock() }
        if invocation.arguments.first == "stop", let index = containers.firstIndex(where: { $0.id == invocation.arguments.last }) {
            containers[index].status.state = .stopped
            return .init(standardOutput: Data(), standardError: Data(), exitCode: 0)
        }
        return .init(standardOutput: (try? JSONEncoder.compose.encode(containers)) ?? Data(), standardError: Data(), exitCode: 0)
    }
}
