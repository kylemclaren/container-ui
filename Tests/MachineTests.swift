import Foundation
import Testing

/// Verifies the machines feature against the exact JSON and argv of
/// `container machine …` (captured live from `container` CLI 1.4.1).
@Suite("Machines")
struct MachineTests {
    private let decoder = ContainerCLI.decoder

    /// `container machine list --format json` — one running (has an IP) and
    /// one stopped machine (no IP, no disk size yet).
    private static let list = """
    [{"diskSize":78249984,"status":"running","createdDate":"2026-09-13T22:24:59Z","ipAddress":"192.168.64.3","id":"dev","memory":1073741824,"cpus":2,"default":true},
     {"status":"stopped","createdDate":"2026-09-13T22:23:59Z","id":"ubuntu","memory":8589934592,"cpus":4,"default":false}]
    """

    /// `container machine inspect dev` — note the CLI escapes slashes here.
    private static let inspect = """
    [{"containerId":"dev-ba1b8b","cpus":2,"createdDate":"2026-09-13T22:24:59Z","diskSize":78249984,"homeMount":"rw","id":"dev",
      "image":{"descriptor":{"digest":"sha256:48b0309ca019d89d40f670aa1bc06e426dc0931948452e8491e3d65087abc07d","mediaType":"application\\/vnd.oci.image.index.v1+json","size":9218},"reference":"docker.io\\/library\\/alpine:3.21"},
      "ipAddress":"192.168.64.3","memory":1073741824,"platform":{"architecture":"arm64","os":"linux"},"startedDate":"2026-09-13T22:25:03Z","status":"running",
      "userSetup":{"gid":20,"uid":501,"username":"kyle"}}]
    """

    // MARK: Decoding

    @Test func listDecodesRunningAndStopped() throws {
        let machines = try decoder.decode([ContainerMachine].self, from: Data(Self.list.utf8))
        #expect(machines.count == 2)
        let dev = try #require(machines.first)
        #expect(dev.id == "dev")
        #expect(dev.isRunning)
        #expect(dev.isDefault)
        #expect(dev.ipAddress == "192.168.64.3")
        #expect(dev.cpus == 2)
        #expect(dev.memory == 1_073_741_824)
        #expect(dev.diskSize == 78_249_984)
        let ubuntu = machines[1]
        #expect(!ubuntu.isRunning && !ubuntu.isDefault)
        #expect(ubuntu.ipAddress == nil && ubuntu.diskSize == nil)
    }

    @Test func inspectDecodesIncludingEscapedSlashes() throws {
        let detail = try #require(try decoder.decode([MachineDetail].self, from: Data(Self.inspect.utf8)).first)
        #expect(detail.containerId == "dev-ba1b8b")
        #expect(detail.imageReference == "docker.io/library/alpine:3.21")
        #expect(detail.homeMount == .rw)
        #expect(detail.userSetup.username == "kyle" && detail.userSetup.uid == 501)
        #expect(detail.platform.display == "linux/arm64")
        #expect(detail.startedDate != nil)
    }

    @Test func unknownStatusIsLenient() throws {
        let json = """
        [{"status":"hibernating","id":"x","memory":1,"cpus":1,"default":false}]
        """
        let machines = try decoder.decode([ContainerMachine].self, from: Data(json.utf8))
        #expect(machines.first?.state == .unknown)
    }

    // MARK: Argument builders

    @Test func listInspectAndLifecycle() {
        #expect(MachineService.listArguments() == ["machine", "list", "--format", "json"])
        #expect(MachineService.inspectArguments(id: "dev") == ["machine", "inspect", "dev"])
        #expect(MachineService.startArguments(id: "dev") == ["machine", "run", "--name", "dev", "--detach", "--", "true"])
        #expect(MachineService.stopArguments(id: "dev") == ["machine", "stop", "dev"])
        #expect(MachineService.deleteArguments(id: "dev") == ["machine", "delete", "dev"])
        #expect(MachineService.setDefaultArguments(id: "dev") == ["machine", "set-default", "dev"])
        #expect(MachineService.shellArguments(id: "dev") == ["machine", "run", "--name", "dev"])
    }

    @Test func createArguments() {
        #expect(MachineService.createArguments(.init(image: "alpine:latest")) == [
            "machine", "create", "--progress", "plain", "alpine:latest",
        ])
        let full = MachineCreateOptions(image: "ubuntu:24.04", name: "dev", cpus: 4, memory: "8G", homeMount: .ro, setDefault: true)
        #expect(MachineService.createArguments(full) == [
            "machine", "create", "--progress", "plain",
            "--name", "dev", "--cpus", "4", "--memory", "8G", "--home-mount", "ro", "--set-default",
            "ubuntu:24.04",
        ])
        // Empty optionals are omitted, not passed as empty flags.
        #expect(MachineService.createArguments(.init(image: "a", name: "", memory: "")) == [
            "machine", "create", "--progress", "plain", "a",
        ])
    }

    @Test func setArgumentsAndSettings() {
        let settings = MachineSettings(cpus: 4, memory: "8G", homeMount: .notMounted, virtualization: true, kernel: "")
        #expect(settings.arguments == ["cpus=4", "memory=8G", "home-mount=none", "virtualization=true", "kernel="])
        #expect(MachineService.setArguments(id: "dev", settings: .init(cpus: 2)) == ["machine", "set", "--name", "dev", "cpus=2"])
        #expect(MachineSettings().isEmpty)
        #expect(MachineSettings(memory: "").isEmpty)
        // Round-trips the CLI's spelling for every case.
        #expect(MachineHomeMount.allCases.map(\.rawValue) == ["rw", "ro", "none"])
    }

    @Test func logsArguments() {
        #expect(MachineService.logsArguments(id: "dev", follow: true, tail: 100, boot: true) == [
            "machine", "logs", "--boot", "-n", "100", "--follow", "dev",
        ])
        #expect(MachineService.logsArguments(id: "dev", follow: false, tail: nil, boot: false) == ["machine", "logs", "dev"])
    }

    // MARK: Validation & formatting

    @Test func nameValidationMirrorsCLI() {
        #expect(MachineService.isValidName("dev"))
        #expect(MachineService.isValidName("ubuntu-24.04_x"))
        #expect(MachineService.isValidName("9lives"))
        #expect(!MachineService.isValidName("d"))            // needs 2+ characters
        #expect(!MachineService.isValidName("-dev"))         // must start alphanumeric
        #expect(!MachineService.isValidName("my machine"))
        #expect(!MachineService.isValidName(String(repeating: "a", count: 64)))
        #expect(MachineService.isValidName(String(repeating: "a", count: 63)))
    }

    @Test func memoryFlagRendering() {
        #expect(MachineService.memoryFlag(fromBytes: 1_073_741_824) == "1G")
        #expect(MachineService.memoryFlag(fromBytes: 8_589_934_592) == "8G")
        #expect(MachineService.memoryFlag(fromBytes: 1_610_612_736) == "1536M")
        #expect(MachineService.memoryFlag(fromBytes: 1) == "1M")
    }

    @Test func startErrorPointsAtInteractiveShellWhenTerminalIsNeeded() {
        let needsTTY = MachineService.startErrorMessage(.commandFailed(code: 1, stderr: "Error: not a tty"))
        #expect(needsTTY.contains("Open shell"))
        let other = MachineService.startErrorMessage(.notFound(message: "container machine with ID x not found"))
        #expect(other == "container machine with ID x not found")
    }

    // MARK: Service

    @Test func listSendsArgsAndDecodes() async throws {
        let mock = MockCommandRunner(stdout: Self.list)
        let machines = try await MachineService(cli: .mock(mock)).list()
        #expect(machines.map(\.id) == ["dev", "ubuntu"])
        #expect(mock.lastArguments == ["machine", "list", "--format", "json"])
    }

    @Test func createStreamsProgressLines() async throws {
        let mock = MockCommandRunner()
        mock.streamLines = [
            .standardError("[2/3] Unpacking image [4s]"),
            .standardOutput("dev"),
        ]
        let service = MachineService(cli: .mock(mock))
        var seen: [String] = []
        for try await line in service.create(.init(image: "alpine:latest", name: "dev")) { seen.append(line.text) }
        #expect(seen == ["[2/3] Unpacking image [4s]", "dev"])
        #expect(mock.lastArguments == ["machine", "create", "--progress", "plain", "--name", "dev", "alpine:latest"])
    }

    @Test func inspectMissingMachineIsNotFound() async {
        let mock = MockCommandRunner(
            stderr: "Error: failed to inspect container machine (cause: \"notFound: \"container machine with ID x not found\"\")",
            exitCode: 1
        )
        let service = MachineService(cli: .mock(mock))
        do {
            _ = try await service.inspect(id: "x")
            Issue.record("expected failure")
        } catch let error as CLIError {
            if case .notFound = error {} else { Issue.record("expected notFound, got \(error)") }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    // MARK: Terminal launcher

    @Test func machineShellArgvAndScript() {
        let argv = TerminalLauncher.machineShellArgv(containerPath: "/usr/local/bin/container", id: "dev")
        #expect(argv == ["/usr/local/bin/container", "machine", "run", "--name", "dev"])
        let body = TerminalLauncher.machineCommandFileBody(containerPath: "/usr/local/bin/container", id: "dev")
        #expect(body.hasPrefix("#!/bin/sh\nrm -f -- \"$0\""))
        #expect(body.contains("'machine · dev'"))
        #expect(body.split(separator: "\n").last == "exec '/usr/local/bin/container' 'machine' 'run' '--name' 'dev'")
    }
}
