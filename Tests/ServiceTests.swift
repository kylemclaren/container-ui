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

    @Test func cleanSendsIDsAndReturnsCleanedList() async throws {
        // `container clean` prints each cleaned id on its own line.
        let mock = MockCommandRunner(stdout: "web\ndb\n")
        let service = ContainerService(cli: .mock(mock))

        let output = try await service.clean(ids: ["web", "db"])

        #expect(output == "web\ndb")
        #expect(mock.lastArguments == ["clean", "web", "db"])
    }

    @Test func cleanOnOlderCLIExplainsVersionRequirement() async {
        // A CLI older than 1.4.1 rejects the unknown subcommand with a
        // usage error (exit 64); the UI should name the version, not the parser.
        let mock = MockCommandRunner(stderr: "Error: Unexpected argument 'clean'", exitCode: 64)
        let service = ContainerService(cli: .mock(mock))

        await #expect(throws: CLIError.usage(message: "Error: Unexpected argument 'clean'")) {
            try await service.clean(ids: ["web"])
        }
        #expect(ContainerService.cleanErrorMessage(.usage(message: "x")) == ContainerService.cleanUnsupportedMessage)
        #expect(ContainerService.cleanErrorMessage(.notFound(message: "no such container: web")) == "no such container: web")
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

    @Test func loginPassesPasswordViaStdinNotArgs() async throws {
        let mock = MockCommandRunner()
        let service = RegistryService(cli: .mock(mock))

        try await service.login(server: "ghcr.io", username: "me", password: "s3cret", scheme: .auto)

        #expect(mock.invocations.last?.standardInput == Data("s3cret".utf8))
        #expect(mock.lastArguments!.contains("--password-stdin"))
        #expect(!mock.lastArguments!.contains("s3cret"))
        #expect(mock.lastArguments!.last == "ghcr.io")
    }

    @Test func loginPropagatesFailure() async {
        let mock = MockCommandRunner(stderr: "unauthorized", exitCode: 1)
        let service = RegistryService(cli: .mock(mock))

        do {
            try await service.login(server: "ghcr.io", username: "me", password: "s3cret", scheme: .auto)
            Issue.record("expected login() to throw")
        } catch is CLIError {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func loggedInHostsParsesQuietAndNormalizes() async throws {
        let mock = MockCommandRunner(stdout: "ghcr.io\nindex.docker.io\n\n")
        let service = RegistryService(cli: .mock(mock))

        let hosts = try await service.loggedInHosts()

        #expect(hosts == ["ghcr.io", "docker.io"])
    }

    @Test func loggedInHostsRawPreservesVerbatimSpelling() async throws {
        // logout(server:) needs the exact stored name — no alias folding/lowercasing.
        let mock = MockCommandRunner(stdout: "index.docker.io\nGHCR.IO\n\n")
        let service = RegistryService(cli: .mock(mock))

        let hosts = try await service.loggedInHostsRaw()

        #expect(hosts == ["index.docker.io", "GHCR.IO"])
    }

    @Test func registryListDecodes() async throws {
        let mock = MockCommandRunner(stdout: Fixtures.registryList)
        let service = RegistryService(cli: .mock(mock))

        let logins = try await service.list()

        #expect(logins.count == 1)
        #expect(logins.first?.hostname == "ghcr.io")
        #expect(logins.first?.username == "kylemclaren")
        #expect(logins.first?.modified != nil)
    }
}
