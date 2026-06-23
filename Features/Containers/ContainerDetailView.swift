import SwiftUI

/// Inspector panel showing the full detail of a container.
struct ContainerDetailView: View {
    let container: Container
    var stats: ContainerStats?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if container.isRunning, let stats {
                    liveStats(stats)
                }

                configuration

                if !container.status.networks.isEmpty {
                    networks
                }

                if !container.configuration.publishedPorts.isEmpty {
                    ports
                }

                if !container.configuration.mounts.isEmpty {
                    mounts
                }

                command

                if !environment.isEmpty {
                    environmentSection
                }

                if !container.configuration.labels.isEmpty {
                    labels
                }
            }
            .padding(18)
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Palette.color(for: container.state).opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.Palette.color(for: container.state))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(container.name)
                        .font(Theme.Typography.title)
                        .textSelection(.enabled)
                        .lineLimit(1)
                    Text(container.imageReference)
                        .font(Theme.Typography.monoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                CopyButton(text: container.id)
            }
            StatusBadge(state: container.state)
        }
    }

    private func liveStats(_ stats: ContainerStats) -> some View {
        section("Live stats") {
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
            HStack(spacing: 18) {
                metric("Block Read", stats.blockReadBytes.map(Formatting.bytes) ?? "—")
                metric("Block Write", stats.blockWriteBytes.map(Formatting.bytes) ?? "—")
            }
        }
    }

    private var configuration: some View {
        section("Configuration") {
            KeyValueRow("Image", container.imageReference, mono: true)
            KeyValueRow("Platform", container.platformDisplay)
            KeyValueRow("CPUs", Formatting.cpus(container.cpus))
            KeyValueRow("Memory", Formatting.bytes(container.memoryInBytes))
            KeyValueRow("Runtime", container.configuration.runtimeHandler)
            KeyValueRow("Created", container.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let started = container.startedAt {
                KeyValueRow("Started", started.formatted(date: .abbreviated, time: .shortened))
            }
            if container.configuration.rosetta {
                KeyValueRow("Rosetta", "Enabled")
            }
        }
    }

    private var networks: some View {
        section("Networks") {
            ForEach(container.status.networks, id: \.network) { attachment in
                VStack(alignment: .leading, spacing: 4) {
                    KeyValueRow("Network", attachment.network)
                    KeyValueRow("IPv4", attachment.ipv4Address, mono: true)
                    KeyValueRow("Gateway", attachment.ipv4Gateway, mono: true)
                    if let mac = attachment.macAddress {
                        KeyValueRow("MAC", mac, mono: true)
                    }
                }
            }
        }
    }

    private var ports: some View {
        section("Published ports") {
            ForEach(container.configuration.publishedPorts) { port in
                Text(port.display).font(Theme.Typography.mono).textSelection(.enabled)
            }
        }
    }

    private var mounts: some View {
        section("Mounts") {
            ForEach(container.configuration.mounts) { mount in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(mount.source) → \(mount.destination)")
                        .font(Theme.Typography.monoCaption)
                        .textSelection(.enabled)
                    if !mount.options.isEmpty {
                        Text(mount.options.joined(separator: ", "))
                            .font(Theme.Typography.monoCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var command: some View {
        section("Command") {
            Text(container.configuration.initProcess.commandLine)
                .font(Theme.Typography.mono)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var environment: [String] { container.configuration.initProcess.environment }

    private var environmentSection: some View {
        section("Environment") {
            ForEach(Array(environment.enumerated()), id: \.offset) { _, entry in
                Text(entry)
                    .font(Theme.Typography.monoCaption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var labels: some View {
        section("Labels") {
            ForEach(container.configuration.labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                KeyValueRow(key, value, mono: true)
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
            Text(label).font(Theme.Typography.monoCaption).foregroundStyle(.secondary)
            Text(value).font(Theme.Typography.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
