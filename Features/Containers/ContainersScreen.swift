import SwiftUI

struct ContainersScreen: View {
    @State private var model: ContainersViewModel
    @Environment(AppModel.self) private var app

    @State private var showRun = false
    @State private var logsTarget: Container?
    @State private var deleteTarget: Container?

    init(service: ContainerService) {
        _model = State(initialValue: ContainersViewModel(service: service))
    }

    var body: some View {
        @Bindable var model = model
        ScreenScaffold(title: "Containers", subtitle: model.subtitle) {
            SearchField(text: $model.searchText, prompt: "Search containers")
            SegmentedPill(
                selection: $model.showAll,
                options: [(value: true, label: "All"), (value: false, label: "Running")]
            )
            .onChange(of: model.showAll) { Task { await model.load() } }
            CircleIconButton(systemImage: "arrow.clockwise", help: "Refresh") {
                Task { await model.load() }
            }
            PillButton(style: .accent) { showRun = true } label: {
                Label("Run", systemImage: "play.fill")
            }
        } content: {
            content
        }
        .task {
            await model.load()
            // Re-check after load: an intent targeting a specific container
            // can arrive before the list exists (palette → fresh screen).
            consume(app.pendingIntent, listLoaded: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await model.loadStats()
            }
        }
        .onChange(of: app.refreshTick) { Task { await model.load() } }
        .onChange(of: app.pendingIntent, initial: true) { _, intent in
            consume(intent, listLoaded: !model.containers.isEmpty)
        }
        .inspector(isPresented: inspectorPresented) {
            inspector
                .inspectorColumnWidth(min: 300, ideal: 350, max: 480)
        }
        .sheet(isPresented: $showRun) {
            RunContainerView(service: model.service) { await model.load() }
        }
        .sheet(item: $logsTarget) { container in
            ContainerLogsView(service: model.service, container: container)
        }
        .confirmationDialog(
            "Delete “\(deleteTarget?.name ?? "")”?",
            isPresented: deleteDialogPresented,
            presenting: deleteTarget
        ) { container in
            Button("Delete", role: .destructive) {
                Task { await model.delete(container, force: container.isRunning) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { container in
            Text(container.isRunning
                 ? "This container is running and will be force-removed."
                 : "This permanently removes the container.")
        }
    }

    /// Consumes a palette intent addressed to this screen. Intents that name a
    /// container wait until the list has loaded (`listLoaded`) so a fresh mount
    /// doesn't drop them; once loaded, unresolvable targets clear the intent.
    private func consume(_ intent: AppIntent?, listLoaded: Bool) {
        switch intent {
        case .runContainer:
            showRun = true
        case .containerLogs(let id):
            guard let container = model.containers.first(where: { $0.id == id }) else {
                if listLoaded { app.clearIntent() }
                return
            }
            logsTarget = container
        case .inspectContainer(let id):
            guard model.containers.contains(where: { $0.id == id }) else {
                if listLoaded { app.clearIntent() }  // target vanished; don't open an empty inspector
                return
            }
            model.selectedID = id
        default:
            return
        }
        app.clearIntent()
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if model.isLoading {
            LoadingView(label: "Loading containers…")
        } else if model.isDaemonDown {
            EmptyStateView(
                systemImage: "bolt.slash",
                title: "The container service isn’t running",
                message: "Start it to manage containers.",
                actionTitle: "Open System",
                actionIcon: "gearshape.2.fill",
                action: { app.select(.system) }
            )
        } else if let message = model.errorMessage, model.containers.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Couldn’t load containers",
                message: message,
                actionTitle: "Retry",
                actionIcon: "arrow.clockwise",
                action: { Task { await model.load() } }
            )
        } else if model.filtered.isEmpty {
            EmptyStateView(
                systemImage: "shippingbox",
                title: model.searchText.isEmpty ? "No containers yet" : "No matches",
                message: model.searchText.isEmpty ? "Run your first container to get started." : nil,
                actionTitle: model.searchText.isEmpty ? "Run a container" : nil,
                action: { showRun = true }
            )
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if let message = model.errorMessage, !model.containers.isEmpty {
                InlineBanner(kind: .error, title: "Action failed", message: message)
                    .padding([.horizontal, .top], 16)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.filtered) { container in
                        ContainerRow(
                            container: container,
                            stats: model.statsByID[container.id],
                            isSelected: model.selectedID == container.id,
                            isBusy: model.busyIDs.contains(container.id),
                            onSelect: {
                                withAnimation(Theme.Motion.snappy) {
                                    model.selectedID = (model.selectedID == container.id) ? nil : container.id
                                }
                            },
                            onConsole: { app.openConsole(container) },
                            onStart: { Task { await model.start(container) } },
                            onStop: { Task { await model.stop(container) } },
                            onRestart: { Task { await model.restart(container) } },
                            onLogs: { logsTarget = container },
                            onKill: { Task { await model.kill(container) } },
                            onDelete: { deleteTarget = container }
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        if let container = model.selected {
            ContainerDetailView(
                container: container,
                stats: model.statsByID[container.id],
                statsPoints: model.history.points(for: container.id)
            )
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Select a container").font(Theme.Typography.body).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Bindings

    private var inspectorPresented: Binding<Bool> {
        Binding(get: { model.selectedID != nil }, set: { if !$0 { model.selectedID = nil } })
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }
}
