import Foundation
import Testing

@Suite("Compose projects")
struct ComposeTests {
    static let yaml = """
    name: example
    services:
      web:
        build: ./web
        ports: ["8080:80"]
        depends_on:
          db:
            condition: service_started
      db:
        image: postgres:17
        profiles: [data]
        volumes: ["data:/var/lib/postgresql/data"]
      debug:
        image: alpine:3.21
        profiles: [debug]
    volumes:
      data: {}
    """

    private func parse(_ yaml: String = Self.yaml) throws -> ComposeManifest {
        try ComposeManifest.parse(yaml, directory: URL(fileURLWithPath: "/tmp/my.project"))
    }

    @Test func previewDependenciesProfilesAndRelativeBuild() throws {
        let manifest = try parse()
        #expect(manifest.name == "example")
        #expect(manifest.canStart)
        #expect(manifest.services.first { $0.name == "web" }?.build == "./web")
        #expect(manifest.services.first { $0.name == "web" }?.ports == ["8080:80"])
        #expect(manifest.enabledServices(profiles: []).map(\.name) == ["db", "web"])
        #expect(manifest.enabledServices(profiles: ["debug"]).map(\.name) == ["db", "debug", "web"])
    }

    @Test func anchorsAndProjectNameMatchBackend() throws {
        let manifest = try parse("""
        x-defaults: &defaults
          image: alpine:3.21
        services:
          first:
            <<: *defaults
          second:
            <<: *defaults
        """)
        #expect(manifest.name == "my_project")
        #expect(manifest.services.allSatisfy { $0.image == "alpine:3.21" })
        #expect(manifest.canStart)
    }

    @Test(arguments: ["", "services: []", "services: {}", "services: [invalid", "hello"])
    func malformedDocumentsFail(_ yaml: String) {
        #expect(throws: (any Error).self) { try parse(yaml) }
    }

    @Test(arguments: ["restart: always", "secrets: [password]", "configs: [config]", "network_mode: host", "hostname: custom", "extends: base", "ports: [{target: 80}]", "volumes: [{type: bind, source: ., target: /app}]", "deploy: {replicas: 3}", "image: '${IMAGE}'"])
    func unsupportedFieldsBlockStart(_ field: String) throws {
        let image = field.hasPrefix("image:") ? "" : "    image: nginx\n"
        let manifest = try parse("services:\n  web:\n\(image)    \(field)\n")
        #expect(!manifest.canStart)
        #expect(manifest.diagnostics.contains { $0.blocking })
    }

    @Test func missingDependenciesAndCyclesBlockStart() throws {
        let missing = try parse("services: {web: {image: nginx, depends_on: [missing]}}")
        #expect(!missing.canStart)
        let cycle = try parse("services: {a: {image: nginx, depends_on: [b]}, b: {image: nginx, depends_on: [a]}}")
        #expect(!cycle.canStart)
    }

    @Test func diagnosticsRemainStableAcrossRepeatedReads() throws {
        let yaml = """
        services: {web: {image: nginx}}
        networks:
          first: {internal: true, driver: overlay}
          second: {ipam: {}, labels: {team: dev}}
        """
        let expected = try parse(yaml)
        for _ in 0..<20 { #expect(try parse(yaml) == expected) }
    }

    @Test func commandArgumentsPreservePathsAndDoNotUseShell() throws {
        let project = ComposeProject(fileURL: URL(fileURLWithPath: "/tmp/a b;$(touch nope)/compose.yaml"), profiles: ["debug", "data"])
        let service = ComposeService(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/container-compose"), containerCLI: .mock(MockCommandRunner()))
        let command = service.invocation(project: project, rebuild: true)
        #expect(command.arguments == ["up", "--file", project.fileURL.path, "--cwd", project.directory.path, "--detach", "--build", "--profile", "data", "--profile", "debug"])
        #expect(command.currentDirectoryURL == project.directory)
        #expect(command.environment?["COMPOSE_PROFILES"] == "")
        #expect(command.environment?["PATH"]?.hasPrefix("/usr/local/bin:") == true)
    }

    @Test func versionGateRejectsOtherBackends() {
        #expect(ComposeService.supports(version: "container-compose version 1.1.0\n"))
        #expect(!ComposeService.supports(version: "container-compose version 0.13.0"))
        #expect(!ComposeService.supports(version: "Docker Compose version v2.0.0"))
    }

    static func container(name: String, project: String?, service: String?, running: Bool = true) throws -> Container {
        var value = try ContainerCLI.decodeJSON([Container].self, from: Data(Fixtures.containerList.utf8))[running ? 0 : 1]
        value.configuration.id = name
        value.configuration.labels = [:]
        value.configuration.labels["com.docker.compose.project"] = project
        value.configuration.labels["com.docker.compose.service"] = service
        return value
    }

    @Test func groupingRequiresOwnershipAndStartRejectsUnrelatedNames() throws {
        let manifest = try parse()
        let ours = try Self.container(name: "example-web", project: "example", service: "web")
        let other = try Self.container(name: "example-debug", project: nil, service: nil)
        #expect(manifest.containers(in: [ours, other]).map(\.id) == ["example-web"])
        try ComposeService.validateStart(manifest: manifest, profiles: [], containers: [ours, other])
        #expect(throws: ComposeError.self) {
            try ComposeService.validateStart(manifest: manifest, profiles: ["debug"], containers: [ours, other])
        }
        let dotted = try Self.container(name: "web.example", project: "other", service: "web")
        #expect(throws: ComposeError.self) { try ComposeService.validateStart(manifest: manifest, profiles: [], containers: [dotted]) }
    }

    @Test func duplicateExplicitNamesAreRejected() throws {
        let manifest = try parse("services: {a: {image: nginx, container_name: shared}, b: {image: nginx, container_name: shared}}")
        #expect(throws: ComposeError.self) { try ComposeService.validateStart(manifest: manifest, profiles: [], containers: []) }
    }

    @Test @MainActor func persistenceRefreshAndForgetDoNotModifySource() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("compose.yaml")
        try Self.yaml.write(to: file, atomically: true, encoding: .utf8)
        let suite = "ComposeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ComposeProjectsModel(defaults: defaults)
        try model.importFile(file)
        try model.importFile(file)
        #expect(model.projects.count == 1)
        let project = try #require(model.selectedProject)
        try model.setProfile("debug", enabled: true, project: project)
        let restored = ComposeProjectsModel(defaults: defaults)
        #expect(restored.projects.first?.profiles == ["debug"])
        #expect(try String(contentsOf: file) == Self.yaml)
        try "broken yaml".write(to: file, atomically: true, encoding: .utf8)
        restored.refreshFiles()
        #expect(restored.fileErrors[project.id] != nil)
        #expect(restored.manifests[project.id]?.name == "example")
        try restored.forget(project)
        #expect(restored.projects.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(ComposeProjectsModel(defaults: defaults).projects.isEmpty)
    }

    @Test @MainActor func duplicateProjectNamesRejected() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "ComposeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ComposeProjectsModel(defaults: defaults)
        for name in ["one.yaml", "two.yaml"] { try Self.yaml.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        try model.importFile(dir.appendingPathComponent("one.yaml"))
        #expect(throws: ComposeError.self) { try model.importFile(dir.appendingPathComponent("two.yaml")) }
    }

    @Test func realRunnerHonorsWorkingDirectory() async throws {
        let dir = URL(fileURLWithPath: "/private/tmp")
        let command = CommandInvocation(executableURL: URL(fileURLWithPath: "/bin/pwd"), arguments: [], currentDirectoryURL: dir)
        let result = try await ProcessCommandRunner().run(command)
        #expect(result.isSuccess)
        #expect(result.standardOutputString.trimmingCharacters(in: .whitespacesAndNewlines) == dir.path)
    }
}
