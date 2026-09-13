import SwiftUI

struct MachinesScreen: View {
    @State private var model: MachinesViewModel
    @Environment(AppModel.self) private var app

    @State private var showCreate = false
    @State private var logsTarget: ContainerMachine?
    @State private var deleteTarget: ContainerMachine?

    init(service: MachineService, containerService: ContainerService) {
        _model = State(initialValue: MachinesViewModel(service: service, containerService: containerService))
    }

    var body: some View {
        @Bindable var model = model
        ScreenScaffold(title: "Machines", subtitle: model.subtitle) {
            SearchField(text: $model.searchText, prompt: "Search machines")
            CircleIconButton(systemImage: "arrow.clockwise", help: "Refresh") {
                Task { await model.load() }
            }
            PillButton(style: .accent) { showCreate = true } label: {
                Label("Create", systemImage: "plus.circle.fill")
            }
        } content: {
            content
        }
        .task {
            await model.load()
            consume(app.pendingIntent, listLoaded: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await model.loadStats()
            }
        }
        .onChange(of: app.refreshTick) { Task { await model.load() } }
        .onChange(of: app.pendingIntent, initial: true) { _, intent in
            consume(intent, listLoaded: !model.machines.isEmpty)
        }
        .inspector(isPresented: inspectorPresented) {
            inspector
                .inspectorColumnWidth(min: 300, ideal: 360, max: 500)
        }
        .sheet(isPresented: $showCreate) {
            CreateMachineView(service: model.service) {
                await model.load()
                await app.refreshMachines()
            }
        }
        .sheet(item: $logsTarget) { machine in
            ContainerLogsView(source: .machine(machine, service: model.service))
        }
        .confirmationDialog(
            "Delete “\(deleteTarget?.name ?? "")”?",
            isPresented: deleteDialogPresented,
            presenting: deleteTarget
        ) { machine in
            Button("Delete", role: .destructive) {
                Task {
                    await model.delete(machine)
                    await app.refreshMachines()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { machine in
            Text(machine.isRunning
                 ? "This stops the machine and deletes it with its persistent disk. Your home directory on the Mac is not affected."
                 : "This deletes the machine and its persistent disk. Your home directory on the Mac is not affected.")
        }
    }

    /// Consumes a palette intent addressed to this screen. Intents that name a
    /// machine wait until the list has loaded so a fresh mount doesn't drop
    /// them; once loaded, unresolvable targets clear the intent.
    private func consume(_ intent: AppIntent?, listLoaded: Bool) {
        switch intent {
        case .createMachine:
            showCreate = true
        case .inspectMachine(let id):
            guard model.machines.contains(where: { $0.id == id }) else {
                if listLoaded { app.clearIntent() }
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
            LoadingView(label: "Loading machines…")
        } else if model.isDaemonDown {
            EmptyStateView(
                systemImage: "bolt.slash",
                title: "The container service isn’t running",
                message: "Start it to manage machines.",
                actionTitle: "Open System",
                actionIcon: "gearshape.2.fill",
                action: { app.select(.system) }
            )
        } else if let message = model.errorMessage, model.machines.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Couldn’t load machines",
                message: message,
                actionTitle: "Retry",
                actionIcon: "arrow.clockwise",
                action: { Task { await model.load() } }
            )
        } else if model.filtered.isEmpty {
            EmptyStateView(
                systemImage: "desktopcomputer",
                title: model.searchText.isEmpty ? "No machines yet" : "No matches",
                message: model.searchText.isEmpty
                    ? "A machine is a persistent Linux environment that boots its own init system and maps your user and home directory in. Create one per distro you target."
                    : nil,
                actionTitle: model.searchText.isEmpty ? "Create a machine" : nil,
                actionIcon: "plus.circle.fill",
                action: { showCreate = true }
            )
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if let message = model.errorMessage, !model.machines.isEmpty {
                InlineBanner(kind: .error, title: "Action failed", message: message)
                    .padding([.horizontal, .top], 16)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.filtered) { machine in
                        MachineRow(
                            machine: machine,
                            detail: model.detailsByID[machine.id],
                            stats: model.statsByID[machine.id],
                            isSelected: model.selectedID == machine.id,
                            isBusy: model.busyIDs.contains(machine.id),
                            onSelect: {
                                withAnimation(Theme.Motion.snappy) {
                                    model.selectedID = (model.selectedID == machine.id) ? nil : machine.id
                                }
                            },
                            onShell: { app.openMachineShell(id: machine.id) },
                            onStart: { Task { await model.start(machine); await app.refreshMachines() } },
                            onStop: { Task { await model.stop(machine); await app.refreshMachines() } },
                            onLogs: { logsTarget = machine },
                            onSetDefault: { Task { await model.setDefault(machine) } },
                            onDelete: { deleteTarget = machine }
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        if let machine = model.selected {
            MachineDetailView(
                machine: machine,
                detail: model.detailsByID[machine.id],
                stats: model.statsByID[machine.id],
                statsPoints: model.history.points(for: machine.id),
                isBusy: model.busyIDs.contains(machine.id),
                onShell: { app.openMachineShell(id: machine.id) },
                onApplySettings: { settings in Task { await model.apply(settings, to: machine) } }
            )
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Select a machine").font(Theme.Typography.body).foregroundStyle(.secondary)
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
