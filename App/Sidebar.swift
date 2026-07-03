import SwiftUI
import AppKit

struct Sidebar: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                        .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { brand }
        .safeAreaInset(edge: .bottom, spacing: 0) { BackendStatusPill().padding(10) }
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
