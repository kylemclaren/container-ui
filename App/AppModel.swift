import SwiftUI
import Observation

/// Sidebar destinations.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case containers
    case images
    case volumes
    case networks
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .containers: return "Containers"
        case .images: return "Images"
        case .volumes: return "Volumes"
        case .networks: return "Networks"
        case .system: return "System"
        }
    }

    var symbol: String {
        switch self {
        case .containers: return "shippingbox.fill"
        case .images: return "square.stack.3d.up.fill"
        case .volumes: return "externaldrive.fill"
        case .networks: return "point.3.filled.connected.trianglepath.dotted"
        case .system: return "gearshape.2.fill"
        }
    }
}

/// Root application state: resolves the `container` binary, exposes services,
/// tracks backend availability, and owns the current sidebar selection.
@MainActor
@Observable
final class AppModel {
    enum Backend: Equatable {
        case checking
        case notInstalled(searched: [String])
        /// Installed, but the system service isn't running.
        case down(message: String)
        case up(SystemStatus)
    }

    var selection: SidebarItem? = .containers
    private(set) var backend: Backend = .checking
    private(set) var cli: ContainerCLI?

    /// All containers (running first), refreshed by the background monitor.
    private(set) var containers: [Container] = []
    /// Running subset — drives the menu bar badge.
    var runningContainers: [Container] { containers.filter(\.isRunning) }
    /// True while a service start/stop initiated from the menu bar is in flight.
    private(set) var isMutatingService = false

    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    /// User override for the binary path (persisted). Empty means "auto-detect".
    var executablePath: String {
        didSet { UserDefaults.standard.set(executablePath, forKey: Self.pathKey); resolve() }
    }

    static let pathKey = "containerExecutablePath"

    /// Which terminal app the one-click console opens (persisted).
    var preferredTerminal: TerminalApp {
        didSet { UserDefaults.standard.set(preferredTerminal.rawValue, forKey: Self.terminalKey) }
    }

    static let terminalKey = "preferredTerminal"

    init() {
        executablePath = UserDefaults.standard.string(forKey: Self.pathKey) ?? ""
        preferredTerminal = UserDefaults.standard.string(forKey: Self.terminalKey)
            .flatMap(TerminalApp.init(rawValue:)) ?? .systemDefault
        resolve()
        ConsoleOpener.sweepStaleScripts()
    }

    var containerService: ContainerService? { cli.map(ContainerService.init) }
    var imageService: ImageService? { cli.map(ImageService.init) }
    var systemService: SystemService? { cli.map(SystemService.init) }
    var volumeService: VolumeService? { cli.map(VolumeService.init) }
    var networkService: NetworkService? { cli.map(NetworkService.init) }

    /// Monotonic counter bumped by the global Refresh command (⌘R).
    /// Screens observe it and reload their own lists.
    private(set) var refreshTick = 0

    /// Re-probes the backend and asks the visible screen to reload.
    func requestRefresh() {
        refreshTick &+= 1
        Task { await refreshBackend() }
    }

    // MARK: Command palette (⌘K)

    var paletteVisible = false

    /// A screen-scoped intent waiting for its target screen to mount and
    /// consume it (via `onChange(of:initial:)`).
    private(set) var pendingIntent: AppIntent?

    /// Snapshots fetched on palette open (containers reuse the 5s monitor).
    private(set) var paletteImages: [ContainerImage] = []
    private(set) var paletteVolumes: [ContainerVolume] = []
    private(set) var paletteNetworks: [ContainerNetwork] = []

    var paletteItems: [PaletteItem] {
        PaletteCatalog.items(
            containers: containers,
            images: paletteImages,
            volumes: paletteVolumes,
            networks: paletteNetworks,
            serviceRunning: isBackendUp
        )
    }

    /// Refreshes the palette's image/volume/network snapshots. Containers are
    /// already kept ≤5s fresh by the background monitor; no extra poll loop.
    func refreshPaletteIndex() async {
        guard isBackendUp else { return }
        async let images = imageService?.list()
        async let volumes = volumeService?.list()
        async let networks = networkService?.list()
        paletteImages = (try? await images) ?? paletteImages
        paletteVolumes = (try? await volumes) ?? paletteVolumes
        paletteNetworks = (try? await networks) ?? paletteNetworks
    }

    /// Executes a palette intent: global ones inline, screen-scoped ones by
    /// navigating and stashing the intent for the screen to consume.
    func dispatch(_ intent: AppIntent) {
        paletteVisible = false
        switch intent {
        case .navigate(let item):
            select(item)
        case .refresh:
            requestRefresh()
        case .startService:
            Task { await startService() }
        case .stopService:
            Task { await stopService() }
        case .startContainer(let id):
            Task { await startContainer(id) }
        case .stopContainer(let id):
            Task { await stopContainer(id) }
        case .openConsole(let id):
            // Global: needs no screen — resolve the container and launch.
            if let container = containers.first(where: { $0.id == id }) {
                openConsole(container)
            }
        case .runContainer, .containerLogs, .inspectContainer:
            select(.containers)
            pendingIntent = intent
        case .pullImage, .runImage, .inspectImage:
            select(.images)
            pendingIntent = intent
        case .createVolume, .inspectVolume:
            select(.volumes)
            pendingIntent = intent
        case .createNetwork, .inspectNetwork:
            select(.networks)
            pendingIntent = intent
        }
    }

    func clearIntent() { pendingIntent = nil }

    private func resolve() {
        let override = executablePath.trimmingCharacters(in: .whitespaces)
        if let url = ContainerExecutable.resolve(override: override.isEmpty ? nil : override) {
            cli = ContainerCLI(executableURL: url)
        } else {
            cli = nil
        }
    }

    /// Re-probes backend availability via `container system status`.
    func refreshBackend() async {
        resolve()
        let newValue: Backend
        if let systemService {
            do {
                let status = try await systemService.status()
                newValue = status.isRunning
                    ? .up(status)
                    : .down(message: status.state == .unregistered
                        ? "The container service isn’t registered yet."
                        : "The container service isn’t running.")
            } catch let error as CLIError {
                switch error {
                case .executableNotFound, .launchFailed:
                    newValue = .notInstalled(searched: ContainerExecutable.searchedPaths)
                default:
                    newValue = .down(message: error.localizedDescription)
                }
            } catch {
                newValue = .down(message: error.localizedDescription)
            }
        } else {
            newValue = .notInstalled(searched: ContainerExecutable.searchedPaths)
        }
        // Avoid needless observation churn (the 5s monitor re-probes constantly).
        if newValue != backend { backend = newValue }
    }

    var isBackendUp: Bool {
        if case .up = backend { return true }
        return false
    }

    // MARK: Background monitoring (drives the menu bar)

    /// Starts a periodic refresh of backend status and running containers.
    /// Idempotent — safe to call from every scene's `.task`.
    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshBackend()
                await self?.refreshContainers()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    /// Refreshes `containers` from `container list --all` (running sorted first);
    /// clears it when the backend isn't up. Transient errors keep the old list.
    func refreshContainers() async {
        guard isBackendUp, let containerService else {
            if !containers.isEmpty { containers = [] }
            return
        }
        guard let all = try? await containerService.list(all: true) else { return }
        let sorted = all.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        if sorted != containers { containers = sorted }
    }

    // MARK: Service & container control (used by the menu bar)

    /// Starts the system service, draining its progress stream to completion.
    func startService() async {
        guard let systemService else { return }
        isMutatingService = true
        defer { isMutatingService = false }
        do { for try await _ in systemService.start() {} } catch {}
        await refreshBackend()
        await refreshContainers()
    }

    func stopService() async {
        guard let systemService else { return }
        isMutatingService = true
        defer { isMutatingService = false }
        _ = try? await systemService.stop()
        await refreshBackend()
        await refreshContainers()
    }

    func startContainer(_ id: String) async {
        guard let containerService else { return }
        _ = try? await containerService.start(id: id)
        await refreshContainers()
    }

    func stopContainer(_ id: String) async {
        guard let containerService else { return }
        _ = try? await containerService.stop(ids: [id])
        await refreshContainers()
    }

    // MARK: One-click console

    /// The user-visible error from the last console-open attempt, if any.
    var consoleError: String?

    /// Opens an interactive shell into `container` in the preferred terminal.
    func openConsole(_ container: Container) {
        guard container.isRunning else {
            consoleError = "“\(container.name)” isn’t running."
            return
        }
        guard let cli else {
            consoleError = "The container CLI couldn’t be found."
            return
        }
        ConsoleOpener.openConsole(
            preferred: preferredTerminal,
            containerPath: cli.executableURL.path,
            id: container.id,
            name: container.name
        ) { [weak self] message in
            self?.consoleError = message
        }
    }

    func select(_ item: SidebarItem) {
        withAnimation(Theme.Motion.smooth) { selection = item }
    }
}
