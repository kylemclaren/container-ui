import Foundation
import Yams
import CryptoKit

/// Only file references are persisted. Compose files and their environment stay on disk.
struct ComposeProject: Codable, Equatable, Identifiable, Sendable {
    let fileURL: URL
    var profiles: [String] = []
    var id: String { fileURL.path }
    var directory: URL { fileURL.deletingLastPathComponent() }

    init(fileURL: URL, profiles: [String] = []) {
        self.fileURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        self.profiles = profiles
    }
}

struct ComposeServicePreview: Identifiable, Equatable, Sendable {
    let name: String
    let image: String?
    let build: String?
    let ports: [String]
    let dependencies: [String]
    let profiles: [String]
    let containerName: String?
    var id: String { name }
}

struct ComposeDiagnostic: Equatable, Identifiable, Sendable {
    let message: String
    let blocking: Bool
    var id: String { message }
}

struct ComposeManifest: Equatable, Sendable {
    let sourceDigest: String
    let name: String
    let services: [ComposeServicePreview]
    let diagnostics: [ComposeDiagnostic]
    var canStart: Bool { !services.isEmpty && !diagnostics.contains(where: \.blocking) }
    var profiles: [String] { Set(services.flatMap(\.profiles)).sorted() }

    func enabledServices(profiles: [String]) -> [ComposeServicePreview] {
        var names = Set(services.filter { $0.profiles.isEmpty || !$0.profiles.allSatisfy { !profiles.contains($0) } }.map(\.name))
        var previous: Set<String> = []
        while previous != names {
            previous = names
            for service in services where names.contains(service.name) { names.formUnion(service.dependencies) }
        }
        return services.filter { names.contains($0.name) }
    }

    /// Match ownership labels, never a name prefix that could include unrelated containers.
    func containers(in all: [Container], service: String? = nil) -> [Container] {
        all.filter {
            $0.configuration.labels["com.docker.compose.project"] == name &&
            (service == nil || $0.configuration.labels["com.docker.compose.service"] == service)
        }
    }

    /// Backend 1.1.0 can remove each of these names during `up`, even without labels.
    func candidateNames(for service: ComposeServicePreview) -> Set<String> {
        var names: Set<String> = ["\(name)-\(service.name)"]
        let domain = name.lowercased().map { "abcdefghijklmnopqrstuvwxyz0123456789-".contains($0) ? String($0) : "-" }
            .joined().split(separator: "-").joined(separator: "-")
        let shortened = String(domain.prefix(63)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if !shortened.isEmpty { names.insert("\(service.name).\(shortened)") }
        if let explicit = service.containerName { names.insert(explicit) }
        return names
    }

    static func read(_ project: ComposeProject) throws -> ComposeManifest {
        let text = try String(contentsOf: project.fileURL, encoding: .utf8)
        return try parse(text, directory: project.directory)
    }

    /// Read-only preview of the backend's input, not a second Compose execution engine.
    /// Known ignored fields are blocked so a stack cannot silently start with different semantics.
    static func parse(_ text: String, directory: URL) throws -> ComposeManifest {
        guard let root = try Yams.load(yaml: text) as? [String: Any],
              let rawServices = root["services"] as? [String: Any], !rawServices.isEmpty else {
            throw ComposeError.invalid("The Compose file must contain a non-empty services mapping.")
        }
        var diagnostics: [ComposeDiagnostic] = []
        func report(_ message: String, blocking: Bool = true) { diagnostics.append(.init(message: message, blocking: blocking)) }
        func unknown(_ map: [String: Any], allowed: Set<String>, path: String) {
            for key in map.keys.sorted() where !allowed.contains(key) && !key.hasPrefix("x-") {
                report("\(path)\(key) is not supported by this Compose integration.")
            }
        }
        unknown(root, allowed: ["name", "version", "services", "networks", "volumes"], path: "")
        let name = root["name"] as? String ?? directory.lastPathComponent.replacingOccurrences(of: ".", with: "_")
        func validName(_ value: String) -> Bool {
            value.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.-]*$", options: .regularExpression) != nil
        }
        if !validName(name) { report("Use a literal project name containing letters, numbers, dots, underscores, or hyphens, starting with a letter or number.") }
        for kind in ["networks", "volumes"] {
            if let definitions = root[kind] as? [String: Any] {
                for (key, value) in definitions {
                    if let options = value as? [String: Any] {
                        unknown(options, allowed: kind == "networks" ? ["name", "external"] : ["name", "external", "driver", "driver_opts", "labels"], path: "\(kind).\(key).")
                        if kind == "networks", options["external"] is [String: Any] {
                            report("networks.\(key): use external: true and a separate name field; external.name is not reliably honored by the backend.")
                        }
                    }
                }
            }
        }
        let allowed: Set<String> = ["image", "build", "deploy", "healthcheck", "volumes", "environment", "env_file", "ports", "command", "depends_on", "user", "container_name", "labels", "networks", "entrypoint", "privileged", "read_only", "working_dir", "platform", "stdin_open", "tty", "mem_limit", "extra_hosts", "profiles"]
        var services: [ComposeServicePreview] = []
        for key in rawServices.keys.sorted() {
            if !validName(key) { report("Invalid service name: \(key). Use letters, numbers, dots, underscores, or hyphens.") }
            guard let service = rawServices[key] as? [String: Any] else {
                report("services.\(key) must be a service mapping."); continue
            }
            unknown(service, allowed: allowed, path: "services.\(key).")
            if let explicit = service["container_name"] as? String, !validName(explicit) {
                report("\(key): container_name must be a literal name containing letters, numbers, dots, underscores, or hyphens.")
            }
            let image = service["image"] as? String
            let buildMap = service["build"] as? [String: Any]
            let build = service["build"] as? String ?? buildMap?["context"] as? String
            if image?.isEmpty != false && service["build"] == nil { report("\(key) needs an image or build context.") }
            if let image, image.contains("$") { report("\(key): image interpolation is not supported by the backend. Use a literal image reference.") }
            for field in ["ports", "volumes"] {
                if let entries = service[field] as? [Any], entries.contains(where: { $0 is [String: Any] }) {
                    report("\(key).\(field): use short syntax; long syntax is not supported by the backend.")
                }
            }
            if let deploy = service["deploy"] as? [String: Any] {
                unknown(deploy, allowed: ["resources"], path: "services.\(key).deploy.")
                if let resources = deploy["resources"] as? [String: Any] {
                    unknown(resources, allowed: ["limits"], path: "services.\(key).deploy.resources.")
                    if let limits = resources["limits"] as? [String: Any] {
                        unknown(limits, allowed: ["cpus", "memory"], path: "services.\(key).deploy.resources.limits.")
                    }
                }
            }
            if let buildMap {
                unknown(buildMap, allowed: ["context", "dockerfile", "args"], path: "services.\(key).build.")
                if build == nil { report("\(key).build needs a context directory.") }
            }
            if let health = service["healthcheck"] as? [String: Any] {
                unknown(health, allowed: ["test", "start_period", "interval", "retries", "timeout"], path: "services.\(key).healthcheck.")
                report("\(key): health checks run during startup; this backend does not provide continuous health monitoring.", blocking: false)
            }
            if let networks = service["networks"] as? [String: Any] {
                for (network, value) in networks {
                    if let options = value as? [String: Any] {
                        unknown(options, allowed: ["aliases"], path: "services.\(key).networks.\(network).")
                    }
                }
            }
            if let dependencies = service["depends_on"] as? [String: Any] {
                for (dependency, value) in dependencies {
                    if let options = value as? [String: Any] {
                        unknown(options, allowed: ["condition"], path: "services.\(key).depends_on.\(dependency).")
                    }
                }
            }
            let dependencies = service["depends_on"] as? [String] ?? (service["depends_on"] as? [String: Any]).map { Array($0.keys).sorted() } ?? []
            let ports = (service["ports"] as? [Any] ?? []).map { String(describing: $0) }
            services.append(.init(name: key, image: image, build: build, ports: ports, dependencies: dependencies,
                                  profiles: service["profiles"] as? [String] ?? [], containerName: service["container_name"] as? String))
        }
        let serviceNames = Set(services.map(\.name))
        for service in services {
            for dependency in service.dependencies where !serviceNames.contains(dependency) {
                report("\(service.name) depends on missing service \(dependency).")
            }
        }
        var visited = Set<String>(), visiting = Set<String>()
        func visit(_ name: String) -> Bool {
            if visiting.contains(name) { return false }
            if visited.contains(name) { return true }
            visiting.insert(name)
            for dependency in services.first(where: { $0.name == name })?.dependencies ?? [] {
                if !visit(dependency) { return false }
            }
            visiting.remove(name); visited.insert(name)
            return true
        }
        if services.contains(where: { !visit($0.name) }) { report("Service dependencies contain a cycle.") }
        report("Container-Compose 1.1.0 provides partial Compose compatibility. Start recreates containers; named volumes are retained. Networks are not automatically isolated per project.", blocking: false)
        if text.contains("${") || FileManager.default.fileExists(atPath: directory.appendingPathComponent(".env").path) {
            report("Environment files and substitutions are resolved by Container-Compose, whose interpolation and precedence differ from Docker Compose. Preview values are the file's source values.", blocking: false)
        }
        return .init(sourceDigest: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined(),
                     name: name, services: services, diagnostics: diagnostics.sorted { $0.message < $1.message })
    }
}

enum ComposeError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): return message } }
}
