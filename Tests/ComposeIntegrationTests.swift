import Foundation
import Testing

/// Opt-in: requires a running Apple container service and container-compose 1.1.0.
/// Unique names ensure cleanup touches only resources created by this test.
@Suite("Compose runtime integration", .enabled(if: ProcessInfo.processInfo.environment["CONTAINER_UI_COMPOSE_INTEGRATION"] == "1"))
struct ComposeIntegrationTests {
    @Test(.timeLimit(.minutes(10))) @MainActor
    func buildStartInspectStopAndRecreateStack() async throws {
        let name = "cui-smoke-" + UUID().uuidString.lowercased().prefix(8)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(name) project")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("web"), withIntermediateDirectories: true)
        let cli = ContainerCLI(executableURL: try #require(ContainerExecutable.resolve(override: nil)))
        let compose = ComposeService(executableURL: try #require(ComposeService.resolve(override: "")), containerCLI: cli)
        let containers = ContainerService(cli: cli)
        let yaml = """
        name: \(name)
        services:
          db:
            image: docker.io/library/redis:7-alpine
            command: [redis-server, --appendonly, 'yes']
            volumes: ["\(name)-data:/data"]
            environment:
              SMOKE_VALUE: from-compose
          web:
            build: ./web
            image: \(name)-web:latest
            depends_on: [db]
          debug:
            image: docker.io/library/alpine:3.21
            command: [sleep, '3600']
            profiles: [debug]
        volumes:
          \(name)-data:
            name: \(name)-data
        """
        try yaml.write(to: dir.appendingPathComponent("compose.yaml"), atomically: true, encoding: .utf8)
        try """
        FROM docker.io/library/nginx:alpine
        RUN echo compose-smoke-ok > /usr/share/nginx/html/index.html
        """.write(to: dir.appendingPathComponent("web/Dockerfile"), atomically: true, encoding: .utf8)
        let project = ComposeProject(fileURL: dir.appendingPathComponent("compose.yaml"))
        let manifest = try ComposeManifest.read(project)
        #expect(manifest.canStart)
        var output: [String] = []

        func cleanup() async throws {
            let owned = manifest.containers(in: try await containers.list())
            if !owned.isEmpty { try await containers.delete(ids: owned.map(\.id), force: true) }
            let volumes = try await VolumeService(cli: cli).list()
            for volume in volumes where volume.name == "\(name)-data" || volume.name == "\(name)_\(name)-data" {
                try await VolumeService(cli: cli).delete(names: [volume.name])
            }
            // Build output is unique to this test; shared base images stay cached.
            _ = try? await ImageService(cli: cli).delete(references: ["\(name)-web:latest"])
            try FileManager.default.removeItem(at: dir)
        }

        do {
            _ = try await compose.checkVersion()
            try await compose.start(project, expected: manifest, rebuild: true) { output.append($0); print($0) }
            var all = try await containers.list()
            let db = try #require(manifest.containers(in: all, service: "db").first)
            let web = try #require(manifest.containers(in: all, service: "web").first)
            #expect(db.isRunning && web.isRunning)
            #expect(manifest.containers(in: all, service: "debug").isEmpty)
            #expect(try await containers.exec(id: web.id, command: ["wget", "-qO-", "http://127.0.0.1:80"]) == "compose-smoke-ok")
            #expect(try await containers.exec(id: db.id, command: ["printenv", "SMOKE_VALUE"]) == "from-compose")
            #expect(try await containers.exec(id: db.id, command: ["redis-cli", "SET", "compose-test", "persisted"]) == "OK")
            // Service DNS/hosts resolution and inter-container connectivity.
            #expect(try await containers.exec(id: web.id, command: ["sh", "-c", "printf 'PING\\r\\n' | nc -w 2 db 6379"]).contains("PONG"))
            #expect(try await containers.logs(id: db.id, tail: 20).contains("Ready to accept connections"))
            try await compose.stop(manifest: manifest) { output.append($0) }
            all = try await containers.list()
            #expect(manifest.containers(in: all).count == 2)
            #expect(manifest.containers(in: all).allSatisfy { !$0.isRunning })
            let withProfile = ComposeProject(fileURL: project.fileURL, profiles: ["debug"])
            try await compose.start(withProfile, expected: manifest, rebuild: false) { output.append($0); print($0) }
            all = try await containers.list()
            #expect(manifest.containers(in: all).filter(\.isRunning).count == 3)
            let newDB = try #require(manifest.containers(in: all, service: "db").first)
            #expect(try await containers.exec(id: newDB.id, command: ["redis-cli", "GET", "compose-test"]) == "persisted")
            // Stop includes previously enabled profiles, independent of current selection.
            try await compose.stop(manifest: manifest) { output.append($0) }
            #expect(try await manifest.containers(in: containers.list()).allSatisfy { !$0.isRunning })
            #expect(!output.isEmpty)
        } catch {
            print("COMPOSE SMOKE OUTPUT:\n" + output.joined(separator: "\n"))
            do { try await cleanup() } catch { Issue.record("Cleanup failed: \(error)") }
            throw error
        }
        try await cleanup()
    }
}
