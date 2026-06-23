import Foundation
import Testing

/// Verifies services drive the runner correctly: argv sent, output decoded, and
/// exit-code/error handling (including the special-case `system status`).
@Suite("Services")
struct ServiceTests {
    @Test func containerListSendsArgsAndDecodes() async throws {
        let mock = MockCommandRunner(stdout: Fixtures.containerList)
        let service = ContainerService(cli: .mock(mock))

        let containers = try await service.list(all: true)

        #expect(containers.count == 2)
        #expect(mock.lastArguments == ["list", "--all", "--format", "json"])
    }

    @Test func statusDecodesDespiteNonZeroExit() async throws {
        // When the service is down, `system status` exits 1 but still prints JSON.
        let mock = MockCommandRunner(stdout: Fixtures.systemStatusUnregistered, exitCode: 1)
        let service = SystemService(cli: .mock(mock))

        let status = try await service.status()

        #expect(status.state == .unregistered)
        #expect(!status.isRunning)
    }

    @Test func diskUsageThrowsDaemonNotRunning() async {
        let mock = MockCommandRunner(
            stderr: "interrupted: \"Ensure container system service has been started with `container system start`.\"",
            exitCode: 1
        )
        let service = SystemService(cli: .mock(mock))

        do {
            _ = try await service.diskUsage()
            Issue.record("expected diskUsage() to throw")
        } catch let error as CLIError {
            guard case .daemonNotRunning = error else {
                Issue.record("expected .daemonNotRunning, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func notFoundIsClassified() async {
        let mock = MockCommandRunner(stderr: "notFound: \"no such container: zzz\"", exitCode: 1)
        let service = ContainerService(cli: .mock(mock))

        do {
            _ = try await service.stop(ids: ["zzz"])
            Issue.record("expected stop() to throw")
        } catch let error as CLIError {
            guard case .notFound = error else {
                Issue.record("expected .notFound, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func imagePullStreamsLines() async throws {
        let mock = MockCommandRunner()
        mock.streamLines = [.standardError("Pulling..."), .standardError("Done")]
        let service = ImageService(cli: .mock(mock))

        var received: [String] = []
        for try await line in service.pull(reference: "nginx") {
            received.append(line.text)
        }

        #expect(received == ["Pulling...", "Done"])
        #expect(mock.lastArguments == ["image", "pull", "--progress", "plain", "nginx"])
    }
}
