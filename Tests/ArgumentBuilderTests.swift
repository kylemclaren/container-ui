import Foundation
import Testing

/// Verifies each service builds the exact argv the `container` CLI expects.
@Suite("Argument builders")
struct ArgumentBuilderTests {
    @Test func containerList() {
        #expect(ContainerService.listArguments(all: true) == ["list", "--all", "--format", "json"])
        #expect(ContainerService.listArguments(all: false) == ["list", "--format", "json"])
    }

    @Test func containerInspectAndStats() {
        #expect(ContainerService.inspectArguments(id: "web") == ["inspect", "web"])
        #expect(ContainerService.statsArguments(ids: ["web", "db"]) == ["stats", "--no-stream", "--format", "json", "web", "db"])
        #expect(ContainerService.statsArguments(ids: []) == ["stats", "--no-stream", "--format", "json"])
    }

    @Test func lifecycle() {
        #expect(ContainerService.startArguments(id: "web") == ["start", "web"])
        #expect(ContainerService.stopArguments(ids: ["web"], time: 5) == ["stop", "--time", "5", "web"])
        #expect(ContainerService.stopArguments(ids: ["a", "b"]) == ["stop", "a", "b"])
        #expect(ContainerService.killArguments(ids: ["web"], signal: "TERM") == ["kill", "--signal", "TERM", "web"])
        #expect(ContainerService.deleteArguments(ids: ["web"], force: true) == ["delete", "--force", "web"])
        #expect(ContainerService.deleteArguments(ids: ["web"], force: false) == ["delete", "web"])
    }

    @Test func logsAndExec() {
        #expect(ContainerService.logsArguments(id: "web", follow: true, tail: 100, boot: false) == ["logs", "-n", "100", "--follow", "web"])
        #expect(ContainerService.logsArguments(id: "web", follow: false, tail: nil, boot: true) == ["logs", "--boot", "web"])
        #expect(ContainerService.execArguments(id: "web", command: ["ls", "-l"]) == ["exec", "web", "ls", "-l"])
    }

    @Test func runOptions() {
        let options = RunOptions(
            image: "nginx:latest",
            name: "web",
            detach: true,
            remove: true,
            env: ["NODE_ENV=production"],
            publishPorts: ["8080:80"],
            volumes: ["/data:/data"],
            cpus: 2,
            memory: "1G",
            command: ["echo", "hi"]
        )
        #expect(ContainerService.runArguments(options) == [
            "run", "--detach", "--rm",
            "--name", "web",
            "--env", "NODE_ENV=production",
            "--publish", "8080:80",
            "--volume", "/data:/data",
            "--cpus", "2",
            "--memory", "1G",
            "nginx:latest",
            "echo", "hi",
        ])
    }

    @Test func minimalRun() {
        let options = RunOptions(image: "alpine")
        #expect(ContainerService.runArguments(options) == ["run", "--detach", "alpine"])
    }

    @Test func containerPrune() {
        #expect(ContainerService.pruneArguments() == ["prune"])
    }

    @Test func images() {
        #expect(ImageService.listArguments() == ["image", "list", "--format", "json"])
        #expect(ImageService.inspectArguments(reference: "alpine") == ["image", "inspect", "alpine"])
        #expect(ImageService.pullArguments(reference: "nginx") == ["image", "pull", "--progress", "plain", "nginx"])
        #expect(ImageService.deleteArguments(references: ["a", "b"], force: true) == ["image", "delete", "--force", "a", "b"])
        #expect(ImageService.deleteArguments(references: ["a"], force: false) == ["image", "delete", "a"])
        #expect(ImageService.tagArguments(source: "a", target: "b") == ["image", "tag", "a", "b"])
    }

    @Test func imagePrune() {
        #expect(ImageService.pruneArguments() == ["image", "prune"])
    }

    @Test func imageBuildMinimal() {
        let options = BuildOptions(contextDirectory: ".")
        #expect(ImageService.buildArguments(options) == ["build", "--progress", "plain", "."])
    }

    @Test func imageBuildFull() {
        let options = BuildOptions(
            contextDirectory: "/src/app",
            tag: "myapp:latest",
            dockerfilePath: "/src/app/Dockerfile",
            buildArgs: ["VERSION=1.2.3", "ENV=prod"],
            labels: ["team=infra"],
            noCache: true,
            target: "builder"
        )
        #expect(ImageService.buildArguments(options) == [
            "build", "--progress", "plain",
            "--tag", "myapp:latest",
            "--file", "/src/app/Dockerfile",
            "--build-arg", "VERSION=1.2.3",
            "--build-arg", "ENV=prod",
            "--label", "team=infra",
            "--no-cache",
            "--target", "builder",
            "/src/app",
        ])
    }

    @Test func imageBuildOmitsEmptyOptionalFlags() {
        // Empty strings are treated as "unset" and must not emit bare flags.
        let options = BuildOptions(contextDirectory: "ctx", tag: "", dockerfilePath: "", target: "")
        #expect(ImageService.buildArguments(options) == ["build", "--progress", "plain", "ctx"])
    }

    @Test func system() {
        #expect(SystemService.statusArguments() == ["system", "status", "--format", "json"])
        #expect(SystemService.dfArguments() == ["system", "df", "--format", "json"])
        #expect(SystemService.versionArguments() == ["system", "version", "--format", "json"])
        #expect(SystemService.startArguments() == ["system", "start", "--enable-kernel-install"])
        #expect(SystemService.stopArguments() == ["system", "stop"])
    }
}
