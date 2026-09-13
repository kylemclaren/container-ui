import SwiftUI
import Observation

@MainActor
@Observable
final class MachinesViewModel {
    let service: MachineService
    /// Live stats come from `container stats` on a machine's backing container.
    let containerService: ContainerService

    var machines: [ContainerMachine] = []
    /// `inspect` output, kept for running machines (for their container id)
    /// and for the selected one.
    var detailsByID: [String: MachineDetail] = [:]
    var statsByID: [String: ContainerStats] = [:]
    /// Rolling CPU/memory series keyed by machine id.
    let history = StatsHistory()
    var isLoading = false
    var errorMessage: String?
    var isDaemonDown = false

    var searchText = ""
    var selectedID: ContainerMachine.ID? {
        didSet { if selectedID != oldValue, selectedID != nil { Task { await loadDetail() } } }
    }
    var busyIDs: Set<String> = []

    init(service: MachineService, containerService: ContainerService) {
        self.service = service
        self.containerService = containerService
    }

    var filtered: [ContainerMachine] {
        guard !searchText.isEmpty else { return machines }
        let query = searchText.lowercased()
        return machines.filter {
            $0.name.lowercased().contains(query)
                || (detailsByID[$0.id]?.imageReference.lowercased().contains(query) ?? false)
        }
    }

    var selected: ContainerMachine? { machines.first { $0.id == selectedID } }
    var selectedDetail: MachineDetail? { selectedID.flatMap { detailsByID[$0] } }
    var runningCount: Int { machines.filter(\.isRunning).count }

    var subtitle: String {
        if machines.isEmpty { return "No machines" }
        return "\(machines.count) total · \(runningCount) running"
    }

    func load() async {
        isLoading = machines.isEmpty
        defer { isLoading = false }
        do {
            let list = try await service.list()
            withAnimation(Theme.Motion.smooth) {
                machines = list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            errorMessage = nil
            isDaemonDown = false
            // The list is enough to render rows; details and stats are
            // per-machine CLI round-trips and must not hold the spinner.
            isLoading = false
            await refreshDetails()
            await loadStats()
        } catch let error as CLIError {
            handle(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-inspects running machines (their backing container id changes per
    /// boot) plus the selection, and drops details for machines that vanished.
    func refreshDetails() async {
        let ids = Set(machines.map(\.id))
        detailsByID = detailsByID.filter { ids.contains($0.key) }
        var wanted = Set(machines.filter(\.isRunning).map(\.id))
        if let selectedID, ids.contains(selectedID) { wanted.insert(selectedID) }
        for id in wanted {
            if let detail = try? await service.inspect(id: id) { detailsByID[id] = detail }
        }
    }

    func loadDetail() async {
        guard let id = selectedID else { return }
        if let detail = try? await service.inspect(id: id) { detailsByID[id] = detail }
    }

    /// Best-effort stats for running machines, fetched via their backing
    /// containers and re-keyed by machine id.
    func loadStats() async {
        let running = machines.filter(\.isRunning)
        var machineByContainer: [String: String] = [:]
        for machine in running {
            if let containerID = detailsByID[machine.id]?.containerId {
                machineByContainer[containerID] = machine.id
            }
        }
        let runningIDs = Set(running.map(\.id))
        guard !machineByContainer.isEmpty else {
            statsByID = [:]
            history.ingest([], runningIDs: runningIDs)
            return
        }
        guard let stats = try? await containerService.stats(ids: Array(machineByContainer.keys)) else { return }
        let remapped: [ContainerStats] = stats.compactMap { stat in
            guard let machineID = machineByContainer[stat.id] else { return nil }
            var copy = stat
            copy.id = machineID
            return copy
        }
        history.ingest(remapped, runningIDs: runningIDs)
        statsByID = Dictionary(remapped.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Actions

    func start(_ machine: ContainerMachine) async {
        await perform(machine.id, describing: MachineService.startErrorMessage) {
            _ = try await self.service.start(id: machine.id)
        }
    }

    func stop(_ machine: ContainerMachine) async {
        await perform(machine.id) { _ = try await self.service.stop(id: machine.id) }
    }

    /// Stops a running machine first: delete removes its persistent disk.
    func delete(_ machine: ContainerMachine) async {
        await perform(machine.id) {
            if machine.isRunning { _ = try await self.service.stop(id: machine.id) }
            _ = try await self.service.delete(id: machine.id)
        }
        if selectedID == machine.id { selectedID = nil }
    }

    func setDefault(_ machine: ContainerMachine) async {
        await perform(machine.id) { _ = try await self.service.setDefault(id: machine.id) }
    }

    /// Applies `machine set` values; they take effect on the next boot.
    func apply(_ settings: MachineSettings, to machine: ContainerMachine) async {
        guard !settings.isEmpty else { return }
        await perform(machine.id) { _ = try await self.service.set(id: machine.id, settings: settings) }
        await loadDetail()
    }

    private func perform(
        _ id: String,
        describing describe: (CLIError) -> String = { $0.localizedDescription },
        _ action: @escaping () async throws -> Void
    ) async {
        busyIDs.insert(id)
        defer { busyIDs.remove(id) }
        do {
            try await action()
            await load()
        } catch let error as CLIError {
            handle(error, message: describe(error))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ error: CLIError, message: String? = nil) {
        errorMessage = message ?? error.localizedDescription
        if error.isBackendUnavailable { isDaemonDown = true }
    }
}
