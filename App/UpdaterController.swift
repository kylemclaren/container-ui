import Combine
import Sparkle
import SwiftUI

/// Owns Sparkle's updater for the app's lifetime and mirrors the pieces SwiftUI
/// needs to observe (whether a check can run, the auto-check preference).
///
/// The feed URL and EdDSA public key live in Info.plist (`SUFeedURL`,
/// `SUPublicEDKey`); Sparkle reads them at startup. `startingUpdater: true`
/// kicks off the scheduled background checks per `SUScheduledCheckInterval`.
@MainActor
final class UpdaterController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Presents Sparkle's "checking for updates" UI.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// Bindable preference for the Settings toggle.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}

/// The "Check for Updates…" menu command, disabled while a check can't run
/// (e.g. one is already in progress).
struct CheckForUpdatesView: View {
    @ObservedObject var updater: UpdaterController

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
