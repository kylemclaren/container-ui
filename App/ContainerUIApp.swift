import SwiftUI

@main
struct ContainerUIApp: App {
    @State private var app = AppModel()
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        // A single main window so the menu bar can re-open it by id.
        Window("ContainerUI", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 940, minHeight: 580)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    app.requestRefresh()
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Command Palette") {
                    app.paletteVisible.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(app)
        } label: {
            MenuBarLabel(app: app)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(app)
                .environmentObject(updater)
        }
    }
}
