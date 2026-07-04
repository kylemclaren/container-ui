import Foundation

/// Everything the command palette can do, expressed as routed intents rather
/// than closures: the target screen usually doesn't exist yet when an item is
/// activated (screens are created per sidebar selection), so screen-scoped
/// intents are stashed on `AppModel.pendingIntent` and consumed by the screen
/// once mounted.
enum AppIntent: Equatable, Hashable, Sendable {
    case navigate(SidebarItem)
    // Containers
    case startContainer(id: String)
    case stopContainer(id: String)
    case containerLogs(id: String)
    case inspectContainer(id: String)
    case openConsole(id: String)
    case runContainer
    // Images
    case runImage(reference: String)
    case inspectImage(id: String)
    case pullImage
    case buildImage
    // Volumes / networks
    case inspectVolume(name: String)
    case createVolume
    case inspectNetwork(name: String)
    case createNetwork
    // System
    case startService
    case stopService
    case refresh
}

/// One row in the command palette.
struct PaletteItem: Identifiable, Equatable {
    enum Category: Int, CaseIterable {
        case action, navigation, container, image, volume, network

        var label: String {
            switch self {
            case .action: return "Actions"
            case .navigation: return "Go to"
            case .container: return "Containers"
            case .image: return "Images"
            case .volume: return "Volumes"
            case .network: return "Networks"
            }
        }
    }

    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let category: Category
    /// Extra searchable text (image reference, short id) beyond the title.
    let keywords: String
    let intent: AppIntent
}

/// Builds the full palette item list from a data snapshot. Pure — testable
/// and independent of how the snapshot is gathered. Destructive operations
/// (delete, kill) are deliberately excluded from the palette.
enum PaletteCatalog {
    static func items(
        containers: [Container],
        images: [ContainerImage],
        volumes: [ContainerVolume],
        networks: [ContainerNetwork],
        serviceRunning: Bool
    ) -> [PaletteItem] {
        var out: [PaletteItem] = []

        // Global actions.
        out.append(.init(
            id: "action.run", title: "Run a container…", subtitle: "Create and start from an image",
            systemImage: "play.fill", category: .action, keywords: "new create", intent: .runContainer
        ))
        out.append(.init(
            id: "action.pull", title: "Pull an image…", subtitle: "Download from a registry",
            systemImage: "arrow.down.circle.fill", category: .action, keywords: "fetch download", intent: .pullImage
        ))
        out.append(.init(
            id: "action.build", title: "Build an image…", subtitle: "Build from a Dockerfile",
            systemImage: "hammer.fill", category: .action, keywords: "dockerfile compile make", intent: .buildImage
        ))
        out.append(.init(
            id: "action.searchHub", title: "Search Docker Hub…", subtitle: "Find images to pull",
            systemImage: "sparkle.magnifyingglass", category: .action,
            keywords: "registry hub search explore find image download", intent: .navigate(.explore)
        ))
        out.append(.init(
            id: "action.createVolume", title: "Create a volume…", subtitle: nil,
            systemImage: "externaldrive.fill.badge.plus", category: .action, keywords: "new storage", intent: .createVolume
        ))
        out.append(.init(
            id: "action.createNetwork", title: "Create a network…", subtitle: nil,
            systemImage: "point.3.filled.connected.trianglepath.dotted", category: .action, keywords: "new subnet", intent: .createNetwork
        ))
        if serviceRunning {
            out.append(.init(
                id: "action.stopService", title: "Stop the container service", subtitle: nil,
                systemImage: "stop.circle.fill", category: .action, keywords: "daemon shutdown", intent: .stopService
            ))
        } else {
            out.append(.init(
                id: "action.startService", title: "Start the container service", subtitle: nil,
                systemImage: "bolt.fill", category: .action, keywords: "daemon boot", intent: .startService
            ))
        }
        out.append(.init(
            id: "action.refresh", title: "Refresh", subtitle: "Re-probe the backend and reload",
            systemImage: "arrow.clockwise", category: .action, keywords: "reload", intent: .refresh
        ))

        // Navigation.
        for item in SidebarItem.allCases {
            out.append(.init(
                id: "nav.\(item.rawValue)", title: "Go to \(item.title)", subtitle: nil,
                systemImage: item.symbol, category: .navigation, keywords: item.rawValue, intent: .navigate(item)
            ))
        }

        // Containers — running first (matters for the empty-query ordering).
        for container in containers.sorted(by: { $0.isRunning && !$1.isRunning }) {
            let stateLabel = container.isRunning ? "running" : "stopped"
            out.append(.init(
                id: "container.inspect.\(container.id)", title: container.name,
                subtitle: "\(container.imageReference) · \(stateLabel)",
                systemImage: "shippingbox.fill", category: .container,
                keywords: container.imageReference, intent: .inspectContainer(id: container.id)
            ))
            if container.isRunning {
                out.append(.init(
                    id: "container.console.\(container.id)", title: "Console: \(container.name)",
                    subtitle: "Open a shell in your terminal",
                    systemImage: "terminal.fill", category: .container,
                    keywords: "\(container.imageReference) shell ssh exec attach",
                    intent: .openConsole(id: container.id)
                ))
                out.append(.init(
                    id: "container.stop.\(container.id)", title: "Stop \(container.name)", subtitle: nil,
                    systemImage: "stop.fill", category: .container,
                    keywords: container.imageReference, intent: .stopContainer(id: container.id)
                ))
            } else {
                out.append(.init(
                    id: "container.start.\(container.id)", title: "Start \(container.name)", subtitle: nil,
                    systemImage: "play.fill", category: .container,
                    keywords: container.imageReference, intent: .startContainer(id: container.id)
                ))
            }
            out.append(.init(
                id: "container.logs.\(container.id)", title: "Logs: \(container.name)", subtitle: nil,
                systemImage: "text.alignleft", category: .container,
                keywords: container.imageReference, intent: .containerLogs(id: container.id)
            ))
        }

        // Images.
        for image in images {
            out.append(.init(
                id: "image.inspect.\(image.id)", title: image.reference, subtitle: "Image",
                systemImage: "square.stack.3d.up.fill", category: .image,
                keywords: "image", intent: .inspectImage(id: image.id)
            ))
            out.append(.init(
                id: "image.run.\(image.id)", title: "Run \(image.reference)…", subtitle: nil,
                systemImage: "play.circle.fill", category: .image,
                keywords: "image", intent: .runImage(reference: image.reference)
            ))
        }

        // Volumes and networks.
        for volume in volumes {
            out.append(.init(
                id: "volume.inspect.\(volume.id)", title: volume.name, subtitle: "Volume · \(volume.format)",
                systemImage: "externaldrive.fill", category: .volume,
                keywords: "volume \(volume.source)", intent: .inspectVolume(name: volume.name)
            ))
        }
        for network in networks {
            out.append(.init(
                id: "network.inspect.\(network.id)", title: network.name,
                subtitle: "Network · \(network.mode)" + (network.status.map { " · \($0.ipv4Subnet)" } ?? ""),
                systemImage: "point.3.filled.connected.trianglepath.dotted", category: .network,
                keywords: "network \(network.status?.ipv4Subnet ?? "")", intent: .inspectNetwork(name: network.name)
            ))
        }
        return out
    }
}

/// Ranks palette items for a query. Pure.
enum PaletteRanker {
    static func rank(_ items: [PaletteItem], query: String) -> [PaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }  // catalog order is the curated default
        return items
            .compactMap { item -> (PaletteItem, Int)? in
                let title = FuzzyMatch.score(trimmed, in: item.title)
                let keywords = FuzzyMatch.score(trimmed, in: item.keywords).map { $0 - 15 }
                guard let best = [title, keywords].compactMap({ $0 }).max() else { return nil }
                return (item, best)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.0.category.rawValue != $1.0.category.rawValue {
                    return $0.0.category.rawValue < $1.0.category.rawValue
                }
                return $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending
            }
            .map(\.0)
    }
}
