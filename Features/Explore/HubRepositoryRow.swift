import SwiftUI
import AppKit

/// A single Docker Hub search result: name, official badge, description, and
/// star/pull counts — swapped for a quick Pull button on hover/selection.
struct HubRepositoryRow: View {
    let repository: HubRepository
    let isSelected: Bool

    var onSelect: () -> Void
    var onPull: () -> Void

    @State private var hovering = false

    private var showActions: Bool { hovering || isSelected }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(repository.repoName)
                            .font(Theme.Typography.headline)
                            .lineLimit(1)
                        if repository.isOfficial { officialBadge }
                    }
                    Text(descriptionText)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack(alignment: .trailing) {
                    stats.opacity(showActions ? 0 : 1)
                    actions.opacity(showActions ? 1 : 0)
                }
                .animation(Theme.Motion.smooth, value: showActions)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menuItems }
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private var icon: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.accentColor.opacity(0.14))
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: repository.isOfficial ? "checkmark.seal.fill" : "shippingbox.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
    }

    private var officialBadge: some View {
        Text("OFFICIAL")
            .font(.system(size: 8.5, weight: .bold))
            .kerning(0.4)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
    }

    private var descriptionText: String {
        let trimmed = (repository.shortDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No description provided." : trimmed
    }

    private var stats: some View {
        HStack(spacing: 6) {
            StatChip(systemImage: "star.fill", text: Formatting.compactCount(repository.starCount))
            StatChip(systemImage: "arrow.down.circle", text: Formatting.compactCount(repository.pullCount))
        }
        .fixedSize()
    }

    private var actions: some View {
        PillButton(style: .accent) { onPull() } label: {
            Label("Pull", systemImage: "arrow.down")
        }
    }

    @ViewBuilder private var menuItems: some View {
        Button("Pull latest…", systemImage: "arrow.down.circle.fill", action: onPull)
        Button("Copy pull reference", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(repository.pullReference(), forType: .string)
        }
    }
}
