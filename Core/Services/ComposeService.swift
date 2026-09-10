import Foundation

struct ComposeService: Sendable {
    let executableURL: URL
    let containerCLI: ContainerCLI
    var runner: CommandRunner = ProcessCommandRunner()

    static func resolve(override: String) -> URL? {
        let paths = override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ["/opt/homebrew/bin/container-compose", "/usr/local/bin/container-compose"]
            : [(override as NSString).expandingTildeInPath]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    static func supports(version: String) -> Bool {
        // Different tools share the executable name. Do not send this backend's flags to them.
        version.trimmingCharacters(in: .whitespacesAndNewlines) == "container-compose version 1.1.0"
    }

    func checkVersion() async throws -> String {
        let result = try await runner.run(.init(executableURL: executableURL, arguments: ["--version"]))
        guard result.isSuccess else { throw CLIError.classify(result) }
        let version = result.standardOutputString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.supports(version: version) else {
            throw ComposeError.invalid("This integration supports Mcrich23/Container-Compose 1.1.0. Found: \(version)")
        }
        return version
    }

    func invocation(project: ComposeProject, rebuild: Bool) -> CommandInvocation {
        var args = ["up", "--file", project.fileURL.path, "--cwd", project.directory.path, "--detach"]
        if rebuild { args.append("--build") }
        for profile in project.profiles.sorted() { args += ["--profile", profile] }
        // The backend shells out to `container`; honor the app's selected CLI directory.
        let path = containerCLI.executableURL.deletingLastPathComponent().path + ":" +
            (ProcessCommandRunner.resolvedEnvironment(nil)["PATH"] ?? "")
        return .init(executableURL: executableURL, arguments: args,
                     environment: ["PATH": path, "COMPOSE_PROFILES": "", "NO_COLOR": "1"],
                     currentDirectoryURL: project.directory)
    }

    static func validateStart(manifest: ComposeManifest, profiles: [String], containers: [Container]) throws {
        guard manifest.canStart else {
            throw ComposeError.invalid(manifest.diagnostics.filter(\.blocking).map(\.message).joined(separator: "\n"))
        }
        let enabled = manifest.enabledServices(profiles: profiles)
        guard !enabled.isEmpty else { throw ComposeError.invalid("Enable a profile to select at least one service.") }
        var owners: [String: String] = [:]
        for service in enabled {
            for candidate in manifest.candidateNames(for: service) {
                if let other = owners[candidate], other != service.name {
                    throw ComposeError.invalid("Services \(other) and \(service.name) share container name \(candidate).")
                }
                owners[candidate] = service.name
                if let existing = containers.first(where: { $0.id == candidate }),
                   existing.configuration.labels["com.docker.compose.project"] != manifest.name ||
                   existing.configuration.labels["com.docker.compose.service"] != service.name {
                    throw ComposeError.invalid("Container \(candidate) already exists outside this service. Choose a different project or container name before starting.")
                }
            }
        }
    }

    /// Reload the file and fetch current runtime state immediately before any mutation.
    func start(_ project: ComposeProject, expected: ComposeManifest, rebuild: Bool,
               onLine: @escaping @MainActor (String) -> Void) async throws {
        _ = try await checkVersion()
        let manifest = try ComposeManifest.read(project)
        guard manifest == expected else { throw ComposeError.invalid("The Compose file changed. Refresh and review it before starting.") }
        let containers = try await ContainerService(cli: containerCLI).list()
        try Self.validateStart(manifest: manifest, profiles: project.profiles, containers: containers)
        for try await line in runner.stream(invocation(project: project, rebuild: rebuild)) {
            await onLine(line.text)
        }
        let after = try await ContainerService(cli: containerCLI).list()
        // A backend may print an error and exit zero. Do not report success if services were never created.
        let missing = manifest.enabledServices(profiles: project.profiles).filter {
            manifest.containers(in: after, service: $0.name).isEmpty
        }
        if !missing.isEmpty {
            throw ComposeError.invalid("No container was created for: \(missing.map(\.name).joined(separator: ", ")). Review the operation output.")
        }
    }

    /// `down` in backend 1.1.0 swallows individual stop errors and guesses names.
    /// Use the supported container CLI on exact ownership labels instead. Includes inactive profiles.
    func stop(manifest: ComposeManifest, onLine: @escaping @MainActor (String) -> Void) async throws {
        let service = ContainerService(cli: containerCLI)
        let owned = manifest.containers(in: try await service.list()).filter(\.isRunning)
        if owned.isEmpty { await onLine("No running containers in this project."); return }
        for container in owned {
            await onLine("Stopping \(container.name)…")
            try await service.stop(ids: [container.id])
        }
        let running = manifest.containers(in: try await service.list()).filter(\.isRunning)
        if !running.isEmpty { throw ComposeError.invalid("Some project containers are still running. Refresh and retry Stop.") }
        await onLine("Project stopped. Containers, volumes, and networks were retained.")
    }
}
