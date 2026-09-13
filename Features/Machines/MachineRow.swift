import SwiftUI
import AppKit

/// A rich, hoverable card representing one container machine.
struct MachineRow: View {
    let machine: ContainerMachine
    /// `inspect` output when known (image reference for the subtitle).
    let detail: MachineDetail?
    let stats: ContainerStats?
    let isSelected: Bool
    let isBusy: Bool

    var onSelect: () -> Void
    var onShell: () -> Void
    var onStart: () -> Void
    var onStop: () -> Void
    var onLogs: () -> Void
    var onSetDefault: () -> Void
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
                    HStack(spacing: 5) {
                        Text(machine.name)
                            .font(Theme.Typography.headline)
                            .lineLimit(1)
                        if machine.isDefault {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .help("Default machine")
                        }
                    }
                    Text(detail?.imageReference ?? "Linux machine")
                        .font(Theme.Typography.monoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack(alignment: .trailing) {
                    HStack(spacing: 6) {
                        metadata
                        StatusBadge(state: machine.state)
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
            .fill(Theme.Palette.color(for: machine.state).opacity(0.16))
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.color(for: machine.state))
            }
    }

    @ViewBuilder private var metadata: some View {
        HStack(spacing: 6) {
            if let ip = machine.ipAddress {
                StatChip(systemImage: "network", text: ip)
            }
            if machine.isRunning, let mem = stats?.memoryUsageBytes {
                StatChip(systemImage: "memorychip", text: Formatting.bytes(mem))
            } else {
                StatChip(systemImage: "cpu", text: Formatting.cpus(machine.cpus))
                StatChip(systemImage: "memorychip", text: Formatting.bytes(machine.memory))
            }
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 6) {
            if isBusy {
                ProgressView().controlSize(.small).frame(width: Theme.Metrics.controlHeight)
            } else if showActions {
                CircleIconButton(systemImage: "terminal", help: machine.isRunning ? "Open shell" : "Boot and open shell", action: onShell)
                if machine.isRunning {
                    CircleIconButton(systemImage: "stop.fill", tint: .orange, help: "Stop", action: onStop)
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
        Button("Open shell", systemImage: "terminal", action: onShell)
        Divider()
        if machine.isRunning {
            Button("Stop", systemImage: "stop.fill", action: onStop)
        } else {
            Button("Start", systemImage: "play.fill", action: onStart)
        }
        Button("View logs", systemImage: "text.alignleft", action: onLogs)
        Divider()
        Button("Set as default", systemImage: "star", action: onSetDefault)
            .disabled(machine.isDefault)
        if let ip = machine.ipAddress {
            Button("Copy IP address", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ip, forType: .string)
            }
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
