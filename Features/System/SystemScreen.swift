import SwiftUI
import AppKit

struct SystemScreen: View {
    @State private var model: SystemViewModel
    @Environment(AppModel.self) private var app

    @State private var pruningContainers = false
    @State private var pruningImages = false
    @State private var cleaningContainers = false
    @State private var showPruneContainers = false
    @State private var showPruneImages = false
    @State private var showCleanContainers = false
    @State private var pruneError: String?

    private var isReclaiming: Bool { pruningContainers || pruningImages || cleaningContainers }

    init(service: SystemService) {
        _model = State(initialValue: SystemViewModel(service: service))
    }

    var body: some View {
        ScreenScaffold(title: "System", subtitle: model.subtitle) {
            CircleIconButton(systemImage: "arrow.clockwise", help: "Refresh") {
                Task { await model.load() }
            }
            if model.isRunning {
                PillButton(style: .destructive) {
                    Task { await model.stop { await app.refreshBackend() } }
                } label: {
                    if model.isStopping { ProgressView().controlSize(.small) }
                    else { Label("Stop service", systemImage: "stop.fill") }
                }
            } else {
                PillButton(style: .accent) {
                    Task { await model.start { await app.refreshBackend() } }
                } label: {
                    if model.isStarting { ProgressView().controlSize(.small) }
                    else { Label("Start service", systemImage: "play.fill") }
                }
            }
        } content: {
            content
        }
        .task { await model.load() }
        .onChange(of: app.refreshTick) { Task { await model.load() } }
        .confirmationDialog(
            "Prune containers?",
            isPresented: $showPruneContainers
        ) {
            Button("Prune containers", role: .destructive) {
                Task { await pruneContainers() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all stopped containers. Running containers are left untouched.")
        }
        .confirmationDialog(
            "Prune images?",
            isPresented: $showPruneImages
        ) {
            Button("Prune images", role: .destructive) {
                Task { await pruneImages() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes dangling and unreferenced images. Images used by a container are left untouched.")
        }
        .confirmationDialog(
            "Clean running containers?",
            isPresented: $showCleanContainers
        ) {
            Button("Clean \(app.runningContainers.count) running") {
                Task { await cleanRunningContainers() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This trims freed blocks on each running container’s root filesystem and named volumes so the host can reclaim the space. Nothing is deleted. Requires container 1.4.1 or later.")
        }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            LoadingView(label: "Checking system…")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusHero

                    if model.isStarting || !model.startLog.isEmpty {
                        startLogCard
                    }

                    if let message = model.errorMessage {
                        InlineBanner(kind: .warning, title: "Something went wrong", message: message)
                    }

                    if !model.versions.isEmpty {
                        versionsCard
                    }

                    if let usage = model.diskUsage {
                        diskUsageSection(usage)
                    }

                    RegistriesSection()
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Status hero

    private var statusHero: some View {
        let running = model.isRunning
        let tint: Color = running ? .green : (model.status?.state == .unregistered ? .red : .orange)
        return HStack(spacing: 14) {
            PulsingDot(color: tint, active: running, size: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(Theme.Typography.title)
                if let subtitle = statusSubtitle {
                    Text(subtitle)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .card()
    }

    private var statusTitle: String {
        switch model.status?.state {
        case .running: return "Running"
        case .unregistered: return "Not registered"
        default: return "Stopped"
        }
    }

    /// Only shown when the service isn't running — a brief call to action. When
    /// running, the dot + "Running" is sufficient (versions live in their card).
    private var statusSubtitle: String? {
        guard !model.isRunning else { return nil }
        switch model.status?.state {
        case .unregistered: return "The container service isn't registered on this system."
        default: return "Start the service to manage containers and images."
        }
    }

    private var startLogCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title: model.isStarting ? "Starting…" : "Start output")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(model.startLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(Theme.Typography.monoCaption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
            .frame(height: 140)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .card(padding: 14)
    }

    private var versionsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title: "Versions")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.versions) { version in
                    HStack(alignment: .firstTextBaseline) {
                        Text(version.appName)
                            .font(Theme.Typography.headline)
                            .frame(width: 170, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(version.version).font(Theme.Typography.body)
                            Text("\(version.buildType) · \(Formatting.shortDigest(version.commit, length: 10))")
                                .font(Theme.Typography.monoCaption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .card(padding: 14)
        }
    }

    private func diskUsageSection(_ usage: DiskUsageStats) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title: "Disk usage")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                DiskUsageCard(title: "Images", systemImage: "square.stack.3d.up.fill", usage: usage.images)
                DiskUsageCard(title: "Containers", systemImage: "shippingbox.fill", usage: usage.containers)
                DiskUsageCard(title: "Volumes", systemImage: "externaldrive.fill", usage: usage.volumes)
            }
            reclaimSpaceRow
        }
    }

    // MARK: Reclaim space

    private var reclaimSpaceRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title: "Reclaim space")
            HStack(spacing: 10) {
                PillButton { showPruneContainers = true } label: {
                    if pruningContainers {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Prune containers", systemImage: "shippingbox")
                    }
                }
                .disabled(app.containerService == nil || isReclaiming)

                PillButton { showPruneImages = true } label: {
                    if pruningImages {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Prune images", systemImage: "square.stack.3d.up")
                    }
                }
                .disabled(app.imageService == nil || isReclaiming)

                PillButton { showCleanContainers = true } label: {
                    if cleaningContainers {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Clean running containers", systemImage: "sparkles")
                    }
                }
                .disabled(app.containerService == nil || app.runningContainers.isEmpty || isReclaiming)
                .help("Trim freed blocks in every running container so the host can reclaim disk space (container 1.4.1+)")

                Spacer()
            }
            if let pruneError {
                Text(pruneError)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 4)
    }

    private func pruneContainers() async {
        guard let containerService = app.containerService else { return }
        pruningContainers = true
        pruneError = nil
        defer { pruningContainers = false }
        do {
            _ = try await containerService.prune()
            await model.load()
        } catch let error as CLIError {
            pruneError = error.localizedDescription
        } catch {
            pruneError = error.localizedDescription
        }
    }

    /// `container clean` on every running container (the monitor keeps
    /// `app.runningContainers` fresh). Nothing is deleted; the CLI skips
    /// read-only roots and `ro` mounts, and reports per-path failures at once.
    private func cleanRunningContainers() async {
        guard let containerService = app.containerService else { return }
        let ids = app.runningContainers.map(\.id)
        guard !ids.isEmpty else { return }
        cleaningContainers = true
        pruneError = nil
        defer { cleaningContainers = false }
        do {
            _ = try await containerService.clean(ids: ids)
            await model.load()
        } catch let error as CLIError {
            pruneError = ContainerService.cleanErrorMessage(error)
        } catch {
            pruneError = error.localizedDescription
        }
    }

    private func pruneImages() async {
        guard let imageService = app.imageService else { return }
        pruningImages = true
        pruneError = nil
        defer { pruningImages = false }
        do {
            _ = try await imageService.prune()
            await model.load()
        } catch let error as CLIError {
            pruneError = error.localizedDescription
        } catch {
            pruneError = error.localizedDescription
        }
    }
}

private struct DiskUsageCard: View {
    let title: String
    let systemImage: String
    let usage: ResourceUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title).font(Theme.Typography.headline)
                Spacer()
            }
            Text(Formatting.bytes(usage.sizeInBytes))
                .font(.system(size: 20, weight: .semibold))
            HStack(spacing: 6) {
                StatChip(systemImage: "number", text: "\(usage.total) total")
                StatChip(systemImage: "bolt.fill", text: "\(usage.active) active")
            }
            if usage.reclaimable > 0 {
                Text("\(Formatting.bytes(usage.reclaimable)) reclaimable")
                    .font(Theme.Typography.monoCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}
