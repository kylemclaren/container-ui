import SwiftUI
import AppKit

/// Large centered empty state with an icon, title, optional message and action.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var actionIcon: String = "plus"
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text(title).font(Theme.Typography.title)
                if let message {
                    Text(message)
                        .font(Theme.Typography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            if let actionTitle, let action {
                PillButton(style: .accent, action: action) {
                    Label(actionTitle, systemImage: actionIcon)
                }
            }
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// Inline status banner used for errors / warnings within a screen.
struct InlineBanner: View {
    enum Kind {
        case error, warning, info

        var tint: Color {
            switch self {
            case .error: return .red
            case .warning: return .orange
            case .info: return .accentColor
            }
        }

        var icon: String {
            switch self {
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    let kind: Kind
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.tint)
                .font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.Typography.headline)
                if let message {
                    Text(message)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                PillButton(style: .standard, action: action) { Text(actionTitle) }
            }
        }
        .padding(14)
        .background(kind.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Metrics.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.cardCorner, style: .continuous)
                .strokeBorder(kind.tint.opacity(0.25), lineWidth: 1)
        }
    }
}

/// A labeled key/value row for detail panels. Value text is selectable.
struct KeyValueRow<Value: View>: View {
    let key: String
    var keyWidth: CGFloat = 120
    @ViewBuilder var value: () -> Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(Theme.Typography.callout)
                .foregroundStyle(.secondary)
                .frame(width: keyWidth, alignment: .leading)
            value()
                .font(Theme.Typography.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension KeyValueRow where Value == AnyView {
    init(_ key: String, _ text: String, mono: Bool = false, keyWidth: CGFloat = 120) {
        self.key = key
        self.keyWidth = keyWidth
        self.value = {
            AnyView(
                Text(text.isEmpty ? "—" : text)
                    .font(mono ? Theme.Typography.mono : Theme.Typography.body)
                    .textSelection(.enabled)
            )
        }
    }
}

/// Small uppercase section label.
struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(Theme.Typography.caption)
            .foregroundStyle(.secondary)
            .kerning(0.6)
    }
}

/// Copies text to the pasteboard with a brief confirmation.
struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        CircleIconButton(
            systemImage: copied ? "checkmark" : "doc.on.doc",
            tint: copied ? .green : .secondary,
            help: "Copy",
            size: 24
        ) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(Theme.Motion.snappy) { copied = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(Theme.Motion.snappy) { copied = false }
            }
        }
    }
}

/// Centered indeterminate loading state.
struct LoadingView: View {
    var label: String = "Loading…"
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(label).font(Theme.Typography.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
