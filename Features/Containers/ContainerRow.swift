import SwiftUI

/// A rich, hoverable card representing one container.
struct ContainerRow: View {
    let container: Container
    let stats: ContainerStats?
    let isSelected: Bool
    let isBusy: Bool

    var onSelect: () -> Void
    var onStart: () -> Void
    var onStop: () -> Void
    var onRestart: () -> Void
    var onLogs: () -> Void
    var onKill: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                iconTile

                VStack(alignment: .leading, spacing: 3) {
                    Text(container.name)
                        .font(Theme.Typography.headline)
                        .lineLimit(1)
                    Text(container.imageReference)
                        .font(Theme.Typography.monoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                metadata

                StatusBadge(state: container.state)

                actions
                    .frame(width: 122, alignment: .trailing)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.rowCorner, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Theme.Palette.hairline,
                              lineWidth: isSelected ? 1.5 : 1)
        }
        .onHover { hovering in
            withAnimation(Theme.Motion.snappy) { self.hovering = hovering }
        }
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Theme.Palette.color(for: container.state).opacity(0.16))
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.color(for: container.state))
            }
    }

    @ViewBuilder private var metadata: some View {
        HStack(spacing: 6) {
            if let ip = container.primaryIPv4Address {
                StatChip(systemImage: "network", text: ip)
            }
            if container.isRunning, let mem = stats?.memoryUsageBytes {
                StatChip(systemImage: "memorychip", text: Formatting.bytes(mem))
            } else {
                StatChip(systemImage: "cpu", text: Formatting.cpus(container.cpus))
            }
        }
        .opacity(hovering ? 0.0 : 1.0)
        .frame(width: hovering ? 0 : nil)
        .animation(Theme.Motion.snappy, value: hovering)
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 6) {
            if isBusy {
                ProgressView().controlSize(.small).frame(width: Theme.Metrics.controlHeight)
            } else if hovering || isSelected {
                if container.isRunning {
                    CircleIconButton(systemImage: "stop.fill", tint: .orange, help: "Stop", action: onStop)
                    CircleIconButton(systemImage: "arrow.clockwise", help: "Restart", action: onRestart)
                } else {
                    CircleIconButton(systemImage: "play.fill", tint: .green, help: "Start", action: onStart)
                }
                CircleIconButton(systemImage: "text.alignleft", help: "Logs", action: onLogs)
                Menu {
                    if container.isRunning {
                        Button("Restart", systemImage: "arrow.clockwise", action: onRestart)
                        Button("Kill", systemImage: "bolt.fill", action: onKill)
                    } else {
                        Button("Start", systemImage: "play.fill", action: onStart)
                    }
                    Button("View logs", systemImage: "text.alignleft", action: onLogs)
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: Theme.Metrics.controlHeight, height: Theme.Metrics.controlHeight)
                        .contentShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: Theme.Metrics.controlHeight)
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.rowCorner, style: .continuous)
            .fill(.thinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.rowCorner, style: .continuous)
                    .fill(hovering ? Theme.Palette.controlBackground : Color.clear)
            }
    }
}
