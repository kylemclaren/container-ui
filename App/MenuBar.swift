import SwiftUI
import AppKit

/// The menu bar glyph: a box that fills when the service is up, badged with the
/// running-container count. Reads `AppModel` directly so it updates live.
struct MenuBarLabel: View {
    let app: AppModel

    var body: some View {
        let count = app.isBackendUp ? app.runningContainers.count : 0
        if count > 0 {
            Label("\(count)", systemImage: "shippingbox.fill")
        } else {
            Image(systemName: app.isBackendUp ? "shippingbox.fill" : "shippingbox")
        }
    }
}

/// The menu bar popover (`.window` style): service status with start/stop, a live
/// list of running containers, and window/quit actions.
///
/// Layout is deliberately overflow-proof: every row trails with a `Spacer` rather
/// than `maxWidth: .infinity`, so the content's *ideal* width is finite and the
/// popover window can never size narrower than the content (which clipped text).
struct MenuBarContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @State private var busyIDs: Set<String> = []
    /// One-shot resource snapshot fetched when the popover opens (and after
    /// row actions) — the applet doesn't run its own stats poll loop.
    @State private var statsByID: [String: ContainerStats] = [:]

    private let width: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            containersSection
            Divider()
            footer
        }
        .frame(width: width)
        // Ensure the monitor is running and refresh immediately so the popover is
        // current on open (rather than up to one poll interval stale).
        .task {
            app.startMonitoring()
            await app.refreshBackend()
            await app.refreshContainers()
            await loadStats()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(stateColor)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text("Container Service").font(Theme.Typography.headline)
                Text(stateText).font(Theme.Typography.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            serviceControl
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var serviceControl: some View {
        switch app.backend {
        case .checking:
            ProgressView().controlSize(.small)
        case .notInstalled:
            EmptyView()
        case .down:
            PillButton(style: .accent) {
                Task { await app.startService() }
            } label: {
                if app.isMutatingService { ProgressView().controlSize(.small) } else { Text("Start") }
            }
            .disabled(app.isMutatingService)
        case .up:
            PillButton(style: .standard) {
                Task { await app.stopService() }
            } label: {
                if app.isMutatingService { ProgressView().controlSize(.small) } else { Text("Stop") }
            }
            .disabled(app.isMutatingService)
        }
    }

    // MARK: Running containers

    @ViewBuilder private var containersSection: some View {
        if app.isBackendUp {
            VStack(spacing: 6) {
                HStack {
                    SectionLabel(title: "Containers")
                    Spacer(minLength: 8)
                    Text(runningSummary)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(app.runningContainers.isEmpty ? Color.secondary : Color.green)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                if app.containers.isEmpty {
                    HStack {
                        Text("No containers")
                            .font(Theme.Typography.callout)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                } else if app.containers.count > Self.scrollThreshold {
                    // A ScrollView never hugs its content, so only introduce one
                    // when the list is genuinely long — and give it a fixed
                    // height so the popover can't clip rows mid-scroll.
                    ScrollView {
                        containerList
                    }
                    .frame(height: 264)
                } else {
                    containerList
                }
            }
        } else {
            HStack {
                Text(offlineMessage)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    /// Beyond this many rows the list scrolls; at or below it, it hugs.
    private static let scrollThreshold = 6

    private var containerList: some View {
        VStack(spacing: 3) {
            ForEach(app.containers) { container in
                MenuContainerRow(
                    container: container,
                    memory: statsByID[container.id]?.memoryUsageBytes.map(Formatting.bytes),
                    busy: busyIDs.contains(container.id),
                    onOpen: { inspect(container.id) },
                    onStart: { run(container.id) { await app.startContainer($0) } },
                    onStop: { run(container.id) { await app.stopContainer($0) } }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 4) {
            MenuActionButton(title: "Open ContainerUI", systemImage: "macwindow") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
                dismiss()
            }
            MenuSettingsLink()
            Spacer(minLength: 8)
            MenuActionButton(title: "Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
    }

    // MARK: State helpers

    /// Runs a per-container action with a busy indicator on that row, then
    /// refreshes the popover's resource snapshot.
    private func run(_ id: String, _ action: @escaping (String) async -> Void) {
        Task {
            busyIDs.insert(id)
            await action(id)
            busyIDs.remove(id)
            await loadStats()
        }
    }

    /// Opens the main window with the container's inspector shown.
    private func inspect(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
        app.dispatch(.inspectContainer(id: id))
        dismiss()
    }

    /// Best-effort one-shot stats fetch for the memory readouts.
    private func loadStats() async {
        guard app.isBackendUp, let service = app.containerService,
              app.containers.contains(where: \.isRunning) else {
            statsByID = [:]
            return
        }
        guard let stats = try? await service.stats() else { return }
        statsByID = Dictionary(stats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var runningSummary: String {
        let count = app.runningContainers.count
        return count == 0 ? "None running" : "\(count) running"
    }

    private var stateText: String {
        switch app.backend {
        case .up: return "Running"
        case .checking: return "Checking…"
        case .down: return "Stopped"
        case .notInstalled: return "Not installed"
        }
    }

    private var stateColor: Color {
        switch app.backend {
        case .up: return .green
        case .checking, .down: return .orange
        case .notInstalled: return .red
        }
    }

    private var offlineMessage: String {
        switch app.backend {
        case .checking: return "Checking the container service…"
        case .down: return "The container service isn’t running. Start it to see your containers."
        case .notInstalled: return "The container CLI isn’t installed."
        case .up: return ""
        }
    }
}

/// One container in the menu bar list: identity, a live memory readout, and a
/// start/stop control. Clicking the row opens its inspector in the main window.
private struct MenuContainerRow: View {
    let container: Container
    let memory: String?
    let busy: Bool
    var onOpen: () -> Void
    var onStart: () -> Void
    var onStop: () -> Void

    @State private var hovering = false

    private var tint: Color { container.isRunning ? .green : .secondary }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 26, height: 26)
                    .overlay {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(tint)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(container.name)
                        .font(Theme.Typography.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(container.imageReference)
                        .font(Theme.Typography.monoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 6)
                if container.isRunning, let memory, !hovering, !busy {
                    Text(memory)
                        .font(Theme.Typography.monoCaption)
                        .foregroundStyle(.secondary)
                }
                if busy {
                    ProgressView().controlSize(.small).frame(width: 24, height: 24)
                } else if container.isRunning {
                    CircleIconButton(systemImage: "stop.fill", tint: .orange, help: "Stop", size: 24, action: onStop)
                        .opacity(hovering ? 1 : 0.6)
                } else {
                    CircleIconButton(systemImage: "play.fill", tint: .green, help: "Start", size: 24, action: onStart)
                        .opacity(hovering ? 1 : 0.6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open in Containers")
        .background(hovering ? Theme.Palette.controlBackground : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovering in withAnimation(Theme.Motion.snappy) { hovering = isHovering } }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Footer Settings affordance, styled to match `MenuActionButton`.
private struct MenuSettingsLink: View {
    @State private var hovering = false

    var body: some View {
        SettingsLink {
            Label("Settings", systemImage: "gearshape")
                .font(Theme.Typography.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(hovering ? Theme.Palette.controlBackground : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in withAnimation(Theme.Motion.snappy) { hovering = isHovering } }
    }
}

/// A subtle, hoverable text+icon button for the menu bar footer.
private struct MenuActionButton: View {
    let title: String
    let systemImage: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Theme.Typography.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(hovering ? Theme.Palette.controlBackground : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in withAnimation(Theme.Motion.snappy) { hovering = isHovering } }
    }
}
