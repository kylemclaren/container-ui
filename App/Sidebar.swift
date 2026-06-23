import SwiftUI

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
        HStack(spacing: 9) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Palette.accentGradient)
            Text("Containers")
                .font(Theme.Typography.title)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 8)
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.Typography.caption).foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle).font(Theme.Typography.monoCaption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
        case .up: return "Service running"
        case .checking: return "Checking…"
        case .down: return "Service stopped"
        case .notInstalled: return "Not installed"
        }
    }

    private var subtitle: String? {
        switch app.backend {
        case .up(let status): return "apiserver \(status.apiServerVersion)"
        case .down, .checking, .notInstalled: return nil
        }
    }
}
