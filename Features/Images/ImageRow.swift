import SwiftUI

struct ImageRow: View {
    let image: ContainerImage
    let isSelected: Bool
    let isBusy: Bool

    var onSelect: () -> Void
    var onTag: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    private var titleText: String {
        let parsed = image.parsedReference
        return parsed.repository + (parsed.tag.map { ":\($0)" } ?? "")
    }

    private var subtitleText: String {
        var parts = [image.shortID]
        let platforms = image.platforms.map(\.display)
        if !platforms.isEmpty { parts.append(platforms.joined(separator: ", ")) }
        if let registry = image.parsedReference.registry, registry != "docker.io" {
            parts.append(registry)
        }
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(titleText)
                        .font(Theme.Typography.headline)
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(Theme.Typography.monoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                StatChip(systemImage: "internaldrive", text: Formatting.bytes(image.displaySize))
                    .opacity(hovering ? 0 : 1)
                    .animation(Theme.Motion.snappy, value: hovering)

                actions
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.rowCorner, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metrics.rowCorner, style: .continuous)
                        .fill(hovering ? Theme.Palette.controlBackground : Color.clear)
                }
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.rowCorner, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Theme.Palette.hairline,
                              lineWidth: isSelected ? 1.5 : 1)
        }
        .onHover { hovering in
            withAnimation(Theme.Motion.snappy) { self.hovering = hovering }
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 6) {
            if isBusy {
                ProgressView().controlSize(.small).frame(width: Theme.Metrics.controlHeight)
            } else if hovering || isSelected {
                CircleIconButton(systemImage: "tag", help: "Tag", action: onTag)
                Menu {
                    Button("Tag…", systemImage: "tag", action: onTag)
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
}
