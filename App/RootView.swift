import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        ZStack {
            NavigationSplitView {
                Sidebar(selection: $app.selection)
                    .navigationSplitViewColumnWidth(min: 212, ideal: 232, max: 300)
            } detail: {
                DetailColumn()
            }
            if app.paletteVisible {
                CommandPaletteView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(Theme.Motion.smooth, value: app.paletteVisible)
        .task { app.startMonitoring() }
        .alert(
            "Couldn’t open console",
            isPresented: Binding(
                get: { app.consoleError != nil },
                set: { if !$0 { app.consoleError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.consoleError ?? "")
        }
    }
}

private struct DetailColumn: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            WindowWash()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(app.selection?.title ?? "ContainerUI")
    }

    @ViewBuilder private var content: some View {
        switch app.backend {
        case .checking:
            LoadingView(label: "Connecting to container…")
        case .notInstalled(let searched):
            NotInstalledView(searched: searched)
        case .down, .up:
            resolvedScreen
        }
    }

    @ViewBuilder private var resolvedScreen: some View {
        if let containerService = app.containerService,
           let imageService = app.imageService,
           let systemService = app.systemService,
           let volumeService = app.volumeService,
           let networkService = app.networkService {
            switch app.selection ?? .containers {
            case .containers: ContainersScreen(service: containerService)
            case .images: ImagesScreen(service: imageService)
            case .explore: ExploreScreen(service: app.dockerHubService)
            case .volumes: VolumesScreen(service: volumeService)
            case .networks: NetworksScreen(service: networkService)
            case .system: SystemScreen(service: systemService)
            }
        } else {
            NotInstalledView(searched: ContainerExecutable.searchedPaths)
        }
    }
}

/// A barely-there accent wash behind detail content for depth.
private struct WindowWash: View {
    var body: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.05), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
