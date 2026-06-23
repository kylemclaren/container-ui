import SwiftUI

/// A capsule search field that matches the pill control language.
struct SearchField: View {
    @Binding var text: String
    var prompt: String = "Search"
    var width: CGFloat = 210

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typography.callout)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(width: width, height: Theme.Metrics.controlHeight)
        .background(Theme.Palette.controlBackground, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
    }
}

/// A two-or-more option segmented pill, styled to match the design language.
struct SegmentedPill<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(Theme.Motion.snappy) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(isSelected ? Color.primary : .secondary)
                        .padding(.horizontal, 12)
                        .frame(height: Theme.Metrics.controlHeight - 6)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "seg", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.Palette.controlBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
