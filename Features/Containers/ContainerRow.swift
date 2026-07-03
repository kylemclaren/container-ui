import SwiftUI
import AppKit

/// A rich, hoverable card representing one container.
struct ContainerRow: View {
    let container: Container
    let stats: ContainerStats?
    let isSelected: Bool
    let isBusy: Bool

    var onSelect: () -> Void
    var onConsole: () -> Void
    var onStart: () -> Void
    var onStop: () -> Void
    var onRestart: () -> Void
    var onLogs: () -> Void
    var onKill: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    /// Actions replace the info cluster in the same trailing slot (no width
    /// animation, so chip text never reflows mid-transition).
    private var showActions: Bool { hovering || isSelected || isBusy }

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

                ZStack(alignment: .trailing) {
                    HStack(spacing: 6) {
                        metadata
                        StatusBadge(state: container.state)
                    }
                    .fixedSize()
                    .opacity(showActions ? 0 : 1)

                    actions
                        .opacity(showActions ? 1 : 0)
                }
                .animation(Theme.Motion.smooth, value: showActions)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menuItems }
        .background(rowBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.rowCorner, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Theme.Palette.hairline,
                              lineWidth: isSelected ? 1.5 : 1)
        }
        .onHover { hovering in
            withAnimation(Theme.Motion.snappy) { self.hovering = hovering }
        }
        // Hug the content's natural height; never stretch to fill the list.
        .fixedSize(horizontal: false, vertical: true)
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
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 6) {
            if isBusy {
                ProgressView().controlSize(.small).frame(width: Theme.Metrics.controlHeight)
            } else if showActions {
                if container.isRunning {
                    CircleIconButton(systemImage: "terminal", help: "Open console", action: onConsole)
                    CircleIconButton(systemImage: "stop.fill", tint: .orange, help: "Stop", action: onStop)
                    CircleIconButton(systemImage: "arrow.clockwise", help: "Restart", action: onRestart)
                } else {
                    CircleIconButton(systemImage: "play.fill", tint: .green, help: "Start", action: onStart)
                }
                CircleIconButton(systemImage: "text.alignleft", help: "Logs", action: onLogs)
                Menu {
                    menuItems
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

    /// Shared contents for the hover ellipsis menu and the row's right-click menu.
    @ViewBuilder private var menuItems: some View {
        if container.isRunning {
            Button("Open console", systemImage: "terminal", action: onConsole)
            Divider()
            Button("Stop", systemImage: "stop.fill", action: onStop)
            Button("Restart", systemImage: "arrow.clockwise", action: onRestart)
            Button("Kill", systemImage: "bolt.fill", action: onKill)
        } else {
            Button("Start", systemImage: "play.fill", action: onStart)
        }
        Button("View logs", systemImage: "text.alignleft", action: onLogs)
        Divider()
        Button("Copy ID", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(container.id, forType: .string)
        }
        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
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
