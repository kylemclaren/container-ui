import SwiftUI
import AppKit

struct SystemScreen: View {
    @State private var model: SystemViewModel
    @Environment(AppModel.self) private var app

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
        return HStack(spacing: 16) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 56, height: 56)
                Image(systemName: running ? "checkmark.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(running ? "Service running" : "Service stopped")
                    .font(Theme.Typography.title)
                if let status = model.status {
                    Text(running
                         ? "\(status.apiServerAppName) \(status.apiServerVersion) (\(status.apiServerBuild))"
                         : "Start the service to manage containers and images.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .card()
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
