import SwiftUI

// MARK: - Surfaces

/// Translucent material surface with a subtle gradient hairline border.
struct CardModifier: ViewModifier {
    var cornerRadius: CGFloat = Theme.Metrics.cardCorner
    var padding: CGFloat? = Theme.Metrics.cardPadding
    var material: Material = .thinMaterial

    func body(content: Content) -> some View {
        Group {
            if let padding { content.padding(padding) } else { content }
        }
        .background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.Palette.borderGradient, lineWidth: 1)
        }
    }
}

extension View {
    func card(
        cornerRadius: CGFloat = Theme.Metrics.cardCorner,
        padding: CGFloat? = Theme.Metrics.cardPadding,
        material: Material = .thinMaterial
    ) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius, padding: padding, material: material))
    }
}

// MARK: - Buttons

/// A soft pill button with hover feedback and accent/destructive variants.
struct PillButton<Label: View>: View {
    enum Style { case standard, accent, destructive }

    var style: Style = .standard
    var height: CGFloat = Theme.Metrics.controlHeight
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var hovering = false

    var body: some View {
        let corner = Theme.Metrics.pillCorner(forHeight: height)
        Button(action: action) {
            label()
                .font(Theme.Typography.caption)
                .foregroundStyle(foreground)
                .frame(height: height)
                .padding(.horizontal, 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(backgroundStyle)
        )
        .overlay {
            if style == .standard {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            }
        }
        .onHover { hovering in
            withAnimation(Theme.Motion.snappy) { self.hovering = hovering }
        }
    }

    private var foreground: Color {
        switch style {
        case .accent: return .white
        case .destructive: return hovering ? .white : .red
        case .standard: return .primary
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        switch style {
        case .accent:
            return AnyShapeStyle(Theme.Palette.accentGradient)
        case .destructive:
            return AnyShapeStyle(hovering ? Color.red : Color.red.opacity(0.12))
        case .standard:
            return AnyShapeStyle(hovering ? Theme.Palette.controlHover : Theme.Palette.controlBackground)
        }
    }
}

/// A round icon button used for inline/hover actions.
struct CircleIconButton: View {
    let systemImage: String
    var tint: Color = .primary
    var help: String = ""
    var size: CGFloat = Theme.Metrics.controlHeight
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(hovering ? Theme.Palette.controlHover : Theme.Palette.controlBackground)
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Motion.snappy) { self.hovering = hovering }
        }
        .help(help)
    }
}

// MARK: - Indicators

/// A status dot that softly pulses while active (e.g. a running container).
struct PulsingDot: View {
    var color: Color
    var active: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            if active {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .scaleEffect(animate ? 2.4 : 1)
                    .opacity(animate ? 0 : 0.6)
            }
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .frame(width: 7, height: 7)
        .onAppear {
            guard active else { return }
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

/// Capsule badge for a container's run state.
struct StatusBadge: View {
    let state: RuntimeState

    var body: some View {
        let color = Theme.Palette.color(for: state)
        HStack(spacing: 6) {
            PulsingDot(color: color, active: state == .running)
            Text(state.displayName).font(Theme.Typography.caption)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }
}

/// A small icon+value chip for inline metadata (cpus, memory, IP…).
struct StatChip: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
            Text(text).font(Theme.Typography.caption)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Theme.Palette.controlBackground,
            in: RoundedRectangle(cornerRadius: Theme.Metrics.chipCorner, style: .continuous)
        )
    }
}

/// A thin progress meter (memory usage etc.).
struct MeterBar: View {
    var fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.controlBackground)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}
