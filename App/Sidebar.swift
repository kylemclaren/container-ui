import SwiftUI
import AppKit

struct Sidebar: View {
    @Binding var selection: SidebarItem?

    /// Core screens shown in the plain navigation list. Explore is pulled out
    /// into its own standout button (see `header`).
    private var listItems: [SidebarItem] { SidebarItem.allCases.filter { $0 != .explore } }

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(listItems) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                        .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { brand }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    /// Pinned to the sidebar bottom: the Explore button sits right above the
    /// backend status pill.
    private var footer: some View {
        VStack(spacing: 8) {
            ExploreSidebarButton(isSelected: selection == .explore) {
                withAnimation(Theme.Motion.smooth) { selection = .explore }
            }
            BackendStatusPill()
        }
        .padding(10)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
            Text("ContainerUI")
                .font(Theme.Typography.title)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

/// The sidebar's standout entry point to Docker Hub search — a distinct accent
/// button rather than a plain navigation row, so discovery feels like its own thing.
private struct ExploreSidebarButton: View {
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        isSelected ? AnyShapeStyle(Color.white.opacity(0.22))
                                   : AnyShapeStyle(Theme.Palette.accentGradient),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .shadow(color: Color.accentColor.opacity(isSelected ? 0 : 0.35), radius: 5, y: 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Explore")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    Text("Search Docker Hub")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
            .shadow(color: isSelected ? Color.accentColor.opacity(0.30) : .clear, radius: 9, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Theme.Motion.snappy) { self.hovering = hovering } }
        .animation(Theme.Motion.smooth, value: isSelected)
    }

    private var fill: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Theme.Palette.accentGradient) }
        return AnyShapeStyle(Color.accentColor.opacity(hovering ? 0.15 : 0.08))
    }

    private var border: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.clear) }
        return AnyShapeStyle(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

/// Compact backend health readout pinned to the sidebar bottom; tapping it jumps
/// to the System tab and re-probes.
struct BackendStatusPill: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.select(.system)
            Task { await app.refreshBackend() }
        } label: {
            HStack(spacing: 9) {
                PulsingDot(color: color, active: app.isBackendUp)
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help("Open System")
    }

    private var color: Color {
        switch app.backend {
        case .up: return .green
        case .checking: return .orange
        case .down: return .orange
        case .notInstalled: return .red
        }
    }

    private var title: String {
        switch app.backend {
        case .up: return "Running"
        case .checking: return "Checking…"
        case .down: return "Stopped"
        case .notInstalled: return "Not installed"
        }
    }
}
