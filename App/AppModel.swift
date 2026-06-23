import SwiftUI
import Observation

/// Sidebar destinations.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case containers
    case images
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .containers: return "Containers"
        case .images: return "Images"
        case .system: return "System"
        }
    }

    var symbol: String {
        switch self {
        case .containers: return "shippingbox.fill"
        case .images: return "square.stack.3d.up.fill"
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

    /// User override for the binary path (persisted). Empty means "auto-detect".
    var executablePath: String {
        didSet { UserDefaults.standard.set(executablePath, forKey: Self.pathKey); resolve() }
    }

    static let pathKey = "containerExecutablePath"

    init() {
        executablePath = UserDefaults.standard.string(forKey: Self.pathKey) ?? ""
        resolve()
    }

    var containerService: ContainerService? { cli.map(ContainerService.init) }
    var imageService: ImageService? { cli.map(ImageService.init) }
    var systemService: SystemService? { cli.map(SystemService.init) }

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
        guard let systemService else {
            backend = .notInstalled(searched: ContainerExecutable.searchedPaths)
            return
        }
        do {
            let status = try await systemService.status()
            backend = status.isRunning ? .up(status) : .down(message: status.state == .unregistered
                ? "The container service isn’t registered yet."
                : "The container service isn’t running.")
        } catch let error as CLIError {
            switch error {
            case .executableNotFound, .launchFailed:
                backend = .notInstalled(searched: ContainerExecutable.searchedPaths)
            default:
                backend = .down(message: error.localizedDescription)
            }
        } catch {
            backend = .down(message: error.localizedDescription)
        }
    }

    var isBackendUp: Bool {
        if case .up = backend { return true }
        return false
    }

    func select(_ item: SidebarItem) {
        withAnimation(Theme.Motion.smooth) { selection = item }
    }
}
