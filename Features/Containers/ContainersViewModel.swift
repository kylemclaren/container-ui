import SwiftUI
import Observation

@MainActor
@Observable
final class ContainersViewModel {
    let service: ContainerService

    var containers: [Container] = []
    var statsByID: [String: ContainerStats] = [:]
    var isLoading = false
    var errorMessage: String?
    var isDaemonDown = false

    var searchText = ""
    var showAll = true
    var selectedID: Container.ID?
    var busyIDs: Set<String> = []

    init(service: ContainerService) {
        self.service = service
    }

    var filtered: [Container] {
        guard !searchText.isEmpty else { return containers }
        let query = searchText.lowercased()
        return containers.filter {
            $0.name.lowercased().contains(query) || $0.imageReference.lowercased().contains(query)
        }
    }

    var selected: Container? { containers.first { $0.id == selectedID } }
    var runningCount: Int { containers.filter(\.isRunning).count }

    var subtitle: String {
        if containers.isEmpty { return "No containers" }
        return "\(containers.count) total · \(runningCount) running"
    }

    func load() async {
        isLoading = containers.isEmpty
        defer { isLoading = false }
        do {
            let list = try await service.list(all: showAll)
            withAnimation(Theme.Motion.smooth) {
                containers = list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            errorMessage = nil
            isDaemonDown = false
            await loadStats()
        } catch let error as CLIError {
            handle(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Refreshes resource stats for running containers (best-effort).
    func loadStats() async {
        guard containers.contains(where: \.isRunning) else {
            statsByID = [:]
            return
        }
        guard let stats = try? await service.stats() else { return }
        statsByID = Dictionary(stats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func start(_ container: Container) async {
        await perform(container.id) { try await self.service.start(id: container.id) }
    }

    func stop(_ container: Container) async {
        await perform(container.id) { _ = try await self.service.stop(ids: [container.id]) }
    }

    func restart(_ container: Container) async {
        await perform(container.id) { try await self.service.restart(id: container.id) }
    }

    func kill(_ container: Container) async {
        await perform(container.id) { _ = try await self.service.kill(ids: [container.id]) }
    }

    func delete(_ container: Container, force: Bool) async {
        await perform(container.id) { _ = try await self.service.delete(ids: [container.id], force: force) }
        if selectedID == container.id { selectedID = nil }
    }

    private func perform(_ id: String, _ action: @escaping () async throws -> Void) async {
        busyIDs.insert(id)
        defer { busyIDs.remove(id) }
        do {
            try await action()
            await load()
        } catch let error as CLIError {
            handle(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ error: CLIError) {
        errorMessage = error.localizedDescription
        if error.isBackendUnavailable { isDaemonDown = true }
    }
}
