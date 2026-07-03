import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @EnvironmentObject private var updater: UpdaterController

    var body: some View {
        @Bindable var app = app
        Form {
            Section("container CLI") {
                TextField(
                    "Binary path",
                    text: $app.executablePath,
                    prompt: Text(ContainerExecutable.defaultInstallPath)
                )
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Browse…", action: chooseBinary)
                    Button("Auto-detect") {
                        app.executablePath = ""
                        Task { await app.refreshBackend() }
                    }
                    Spacer()
                    Button("Recheck") { Task { await app.refreshBackend() } }
                }

                Label(statusText, systemImage: statusIcon)
                    .font(.callout)
                    .foregroundStyle(statusColor)
            }

            Section("Console") {
                Picker("Open console in", selection: $app.preferredTerminal) {
                    ForEach(ConsoleOpener.installedTerminals()) { terminal in
                        Text(terminal.displayName).tag(terminal)
                    }
                }
                Text("One-click console opens an interactive shell in this terminal app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                HStack {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Spacer()
                }
                Text("Updates are downloaded from GitHub Releases and verified with a built-in signing key.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 400)
    }

    private var statusText: String {
        if let cli = app.cli { return "Using \(cli.executableURL.path)" }
        return "Not found — auto-detect failed."
    }

    private var statusIcon: String {
        app.cli == nil ? "xmark.circle.fill" : "checkmark.circle.fill"
    }

    private var statusColor: Color {
        app.cli == nil ? .red : .green
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
