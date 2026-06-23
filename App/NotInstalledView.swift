import SwiftUI
import AppKit

/// Shown when the `container` binary can't be found. Offers auto-detect, manual
/// selection, and a download link.
struct NotInstalledView: View {
    let searched: [String]
    @Environment(AppModel.self) private var app

    private let releasesURL = URL(string: "https://github.com/apple/container/releases")!

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "shippingbox")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 7) {
                Text("container isn’t installed")
                    .font(Theme.Typography.largeTitle)
                Text("Couldn’t find Apple’s container command-line tool. Install it, then point this app at the binary.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(title: "Searched")
                ForEach(searched, id: \.self) { path in
                    Text(path).font(Theme.Typography.monoCaption).foregroundStyle(.secondary)
                }
            }
            .card(padding: 14)
            .frame(maxWidth: 420)

            HStack(spacing: 10) {
                PillButton(style: .accent, action: chooseBinary) {
                    Label("Choose binary…", systemImage: "folder")
                }
                PillButton(action: { Task { await app.refreshBackend() } }) {
                    Label("Recheck", systemImage: "arrow.clockwise")
                }
                Link(destination: releasesURL) {
                    Label("Download", systemImage: "arrow.down.circle")
                        .font(Theme.Typography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            app.executablePath = url.path
            Task { await app.refreshBackend() }
        }
    }
}
