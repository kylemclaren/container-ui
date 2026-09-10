import Foundation
import Observation

/// Owned by AppModel so navigation never abandons an in-flight project operation.
@MainActor @Observable
final class ComposeProjectsModel {
    private(set) var projects: [ComposeProject] = []
    var selection: String?
    private(set) var manifests: [String: ComposeManifest] = [:]
    private(set) var fileErrors: [String: String] = [:]
    private(set) var output: [String] = []
    private(set) var operationProject: String?
    private(set) var operationTitle: String?
    private(set) var isBusy = false
    var errorMessage: String?
    var backendVersion: String?
    var backendError: String?
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "composeProjects.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            do { projects = try JSONDecoder().decode([ComposeProject].self, from: data) }
            catch { errorMessage = "Saved projects could not be read: \(error.localizedDescription)" }
        }
        selection = projects.first?.id
        refreshFiles()
    }

    var selectedProject: ComposeProject? { projects.first { $0.id == selection } }

    func importFile(_ url: URL) throws {
        let project = ComposeProject(fileURL: url)
        let manifest = try ComposeManifest.read(project)
        if !projects.contains(where: { $0.id == project.id }) {
            try checkName(manifest.name, excluding: project.id)
            projects.append(project)
            try persist()
        }
        manifests[project.id] = manifest
        fileErrors[project.id] = nil
        selection = project.id
    }

    func forget(_ project: ComposeProject) throws {
        guard !isBusy else { return }
        projects.removeAll { $0.id == project.id }
        manifests[project.id] = nil
        fileErrors[project.id] = nil
        selection = projects.first?.id
        try persist()
    }

    func setProfile(_ profile: String, enabled: Bool, project: ComposeProject) throws {
        guard !isBusy, let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].profiles.removeAll { $0 == profile }
        if enabled { projects[index].profiles.append(profile) }
        try persist()
    }

    func refreshFiles() {
        guard !isBusy else { return }
        for project in projects {
            do {
                manifests[project.id] = try ComposeManifest.read(project)
                fileErrors[project.id] = nil
            } catch {
                // Retain last successful preview so Stop can still use ownership labels.
                fileErrors[project.id] = error.localizedDescription
            }
        }
    }

    func checkBackend(_ service: ComposeService?) async {
        backendVersion = nil
        guard let service else {
            backendError = "Install Container-Compose 1.1.0, or choose its executable in Settings."
            return
        }
        do { backendVersion = try await service.checkVersion(); backendError = nil }
        catch { backendError = error.localizedDescription }
    }

    func run(project: ComposeProject, service: ComposeService, stop: Bool, rebuild: Bool = false) async {
        guard !isBusy, let manifest = manifests[project.id] else { return }
        isBusy = true
        operationProject = manifest.name
        operationTitle = stop ? "Stopping" : (rebuild ? "Rebuilding" : "Starting")
        output = []; errorMessage = nil
        defer { isBusy = false; refreshFiles() }
        do {
            if stop {
                try await service.stop(manifest: manifest) { self.append($0) }
            } else {
                try checkName(manifest.name, excluding: project.id)
                try await service.start(project, expected: manifest, rebuild: rebuild) { self.append($0) }
            }
            operationTitle = "Completed"
        } catch {
            operationTitle = "Failed"
            errorMessage = error.localizedDescription
            append(error.localizedDescription)
        }
    }

    private func checkName(_ name: String, excluding id: String) throws {
        for project in projects where project.id != id {
            // Reload other files too: external edits may introduce a collision.
            let manifest = try ComposeManifest.read(project)
            if manifest.name == name {
                throw ComposeError.invalid("Another imported project uses the name \(name). Set a unique top-level name in the Compose file.")
            }
        }
    }

    private func append(_ line: String) {
        output.append(line)
        if output.count > 3000 { output.removeFirst(output.count - 3000) }
    }

    private func persist() throws { defaults.set(try JSONEncoder().encode(projects), forKey: Self.storageKey) }
}
