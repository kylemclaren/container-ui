import SwiftUI

/// Consistent screen chrome: a large title, optional subtitle, a trailing
/// toolbar area, and a content region below a hairline divider.
struct ScreenScaffold<ToolbarContent: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var toolbar: () -> ToolbarContent
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.Typography.largeTitle)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.Typography.callout)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(Theme.Motion.smooth, value: subtitle)
                    }
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) { toolbar() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider().opacity(0.4)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
