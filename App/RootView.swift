import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            Sidebar(selection: $app.selection)
                .navigationSplitViewColumnWidth(min: 212, ideal: 232, max: 300)
        } detail: {
            DetailColumn()
        }
        .task { await app.refreshBackend() }
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
           let systemService = app.systemService {
            switch app.selection ?? .containers {
            case .containers: ContainersScreen(service: containerService)
            case .images: ImagesScreen(service: imageService)
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
