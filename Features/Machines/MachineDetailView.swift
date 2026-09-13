import SwiftUI

/// Inspector panel for a container machine: identity, live stats (via the
/// backing container), configuration, and editable boot settings.
struct MachineDetailView: View {
    let machine: ContainerMachine
    var detail: MachineDetail?
    var stats: ContainerStats?
    /// Rolling CPU/memory series for the live chart (empty hides the chart).
    var statsPoints: [StatsPoint] = []
    var isBusy = false
    var onShell: () -> Void
    var onApplySettings: (MachineSettings) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if machine.isRunning, let stats {
                    liveStats(stats)
                }

                configuration

                MachineSettingsCard(machine: machine, detail: detail, isBusy: isBusy, onApply: onApplySettings)

                user
            }
            .padding(18)
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Palette.color(for: machine.state).opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.Palette.color(for: machine.state))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(machine.name)
                            .font(Theme.Typography.title)
                            .textSelection(.enabled)
                            .lineLimit(1)
                        if machine.isDefault {
                            Text("Default")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(detail?.imageReference ?? "Linux machine")
                        .font(Theme.Typography.monoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                CopyButton(text: machine.id)
            }
            HStack(spacing: 10) {
                StatusBadge(state: machine.state)
                Spacer(minLength: 0)
                PillButton(style: .accent) { onShell() } label: {
                    Label(machine.isRunning ? "Shell" : "Boot & shell", systemImage: "terminal")
                }
                .help("Open a login shell as your user, with your home directory mounted")
            }
        }
    }

    private func liveStats(_ stats: ContainerStats) -> some View {
        section("Live stats") {
            if !statsPoints.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("CPU").font(Theme.Typography.callout).foregroundStyle(.secondary)
                        Spacer()
                        Text(statsPoints.last?.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—")
                            .font(Theme.Typography.caption)
                            .contentTransition(.numericText())
                    }
                    CPUChart(points: statsPoints)
                }
            }
            if let fraction = stats.memoryFraction {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Memory").font(Theme.Typography.callout).foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatting.memory(used: stats.memoryUsageBytes, limit: stats.memoryLimitBytes))
                            .font(Theme.Typography.caption)
                    }
                    MeterBar(fraction: fraction, tint: fraction > 0.85 ? .orange : .accentColor)
                }
            }
            HStack(spacing: 18) {
                metric("Net Rx", stats.networkRxBytes.map(Formatting.bytes) ?? "—")
                metric("Net Tx", stats.networkTxBytes.map(Formatting.bytes) ?? "—")
                metric("Processes", stats.numProcesses.map { "\($0)" } ?? "—")
            }
        }
    }

    private var configuration: some View {
        section("Configuration") {
            KeyValueRow("Image", detail?.imageReference ?? "—", mono: true)
            KeyValueRow("Platform", detail?.platform.display ?? "—")
            KeyValueRow("CPUs", Formatting.cpus(machine.cpus))
            KeyValueRow("Memory", Formatting.bytes(machine.memory))
            KeyValueRow("Disk", machine.diskSize.map { Formatting.bytes($0) } ?? "—")
            KeyValueRow("Home mount", detail?.homeMount.displayName ?? "—")
            KeyValueRow("IP address", machine.ipAddress ?? "—", mono: true)
            KeyValueRow("Created", machine.createdDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            if let started = detail?.startedDate, machine.isRunning {
                KeyValueRow("Started", Formatting.relative(started))
            }
            if let containerID = detail?.containerId, machine.isRunning {
                KeyValueRow("Container", containerID, mono: true)
            }
        }
    }

    @ViewBuilder private var user: some View {
        if let setup = detail?.userSetup {
            section("Linux user") {
                KeyValueRow("Username", setup.username, mono: true)
                KeyValueRow("UID / GID", "\(setup.uid) / \(setup.gid)", mono: true)
                Text("Matches your macOS account, so files you touch in the mounted home directory keep the same owner.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title: title)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.Typography.caption).foregroundStyle(.secondary)
            Text(value).font(Theme.Typography.body).monospacedDigit()
        }
    }
}

/// Editable `machine set` values. Changes land on disk immediately and apply
/// on the next boot, so a running machine is told to restart.
private struct MachineSettingsCard: View {
    let machine: ContainerMachine
    let detail: MachineDetail?
    let isBusy: Bool
    let onApply: (MachineSettings) -> Void

    @State private var cpus: Int = 1
    @State private var memory: String = ""
    @State private var homeMount: MachineHomeMount = .rw
    @State private var applied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title: "Settings")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CPUs").font(Theme.Typography.body)
                    Spacer()
                    Stepper(value: $cpus, in: 1...64) {
                        Text("\(cpus)").font(Theme.Typography.body).monospacedDigit().frame(minWidth: 24, alignment: .trailing)
                    }
                }
                HStack {
                    Text("Memory").font(Theme.Typography.body)
                    Spacer()
                    TextField("e.g. 8G", text: $memory)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Home directory").font(Theme.Typography.body)
                    Spacer()
                    Picker("", selection: $homeMount) {
                        ForEach(MachineHomeMount.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                HStack(spacing: 10) {
                    Text(hint)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    PillButton { apply() } label: {
                        if isBusy { ProgressView().controlSize(.small) }
                        else { Label("Apply", systemImage: "checkmark") }
                    }
                    .disabled(pending.isEmpty || isBusy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
        }
        .task(id: machine.id) { reset() }
        .onChange(of: detail) { reset() }
    }

    private var currentMemory: String { MachineService.memoryFlag(fromBytes: machine.memory) }

    /// Only the fields that differ from the machine's current values.
    private var pending: MachineSettings {
        var settings = MachineSettings()
        if cpus != machine.cpus { settings.cpus = cpus }
        let trimmed = memory.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed.caseInsensitiveCompare(currentMemory) != .orderedSame { settings.memory = trimmed }
        if let current = detail?.homeMount, homeMount != current { settings.homeMount = homeMount }
        return settings
    }

    private var hint: String {
        if applied && machine.isRunning { return "Saved. Restart the machine to apply." }
        if applied { return "Saved. Applies on next boot." }
        return machine.isRunning ? "Changes take effect after a restart." : "Changes take effect on the next boot."
    }

    private func reset() {
        cpus = machine.cpus
        memory = currentMemory
        homeMount = detail?.homeMount ?? .rw
    }

    private func apply() {
        let settings = pending
        guard !settings.isEmpty else { return }
        applied = true
        onApply(settings)
    }
}
