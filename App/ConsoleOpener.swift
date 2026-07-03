import AppKit

/// The effectful side of the one-click console: writes the bootstrap script
/// and launches the user's preferred terminal. Pure command/script building
/// lives in `TerminalLauncher` (Core), where it's unit-tested.
@MainActor
enum ConsoleOpener {
    enum ConsoleError: LocalizedError {
        case scriptWriteFailed(underlying: Error)
        case launchFailed(app: String)

        var errorDescription: String? {
            switch self {
            case .scriptWriteFailed(let underlying):
                return "Couldn’t prepare the console script: \(underlying.localizedDescription)"
            case .launchFailed(let app):
                return "Couldn’t open \(app)."
            }
        }
    }

    /// Terminals worth offering in Settings: system default plus whatever is
    /// actually installed (resolved through Launch Services, so /Applications,
    /// ~/Applications, Setapp, etc. all count).
    static func installedTerminals() -> [TerminalApp] {
        TerminalApp.allCases.filter { app in
            guard let bundleID = app.bundleIdentifier else { return true }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }
    }

    /// Opens an interactive shell into `id` in the preferred terminal.
    /// A chosen-but-missing terminal degrades to the system-default path.
    /// All failures (sync and async Launch Services callbacks alike) are
    /// reported through `onFailure` on the main actor.
    static func openConsole(
        preferred: TerminalApp,
        containerPath: String,
        id: String,
        name: String,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        let execArgv = TerminalLauncher.execArgv(containerPath: containerPath, id: id)

        if let extraArgs = TerminalLauncher.terminalArguments(for: preferred, execArgv: execArgv),
           let bundleID = preferred.bundleIdentifier,
           NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
            // Argv terminal: `open -na <App> --args …` — a running single-instance
            // terminal drops NSWorkspace launch arguments, but `open -na` reliably
            // forces a new instance/window that receives them.
            launchViaOpen(
                arguments: ["-n", "-b", bundleID, "--args"] + extraArgs,
                appName: preferred.displayName,
                onFailure: onFailure
            )
            return
        }

        // Script path: write a self-deleting `.command` and open it.
        let scriptURL: URL
        do {
            scriptURL = try writeScript(containerPath: containerPath, id: id, name: name)
        } catch {
            onFailure(error.localizedDescription)
            return
        }
        var fellBack = false
        let fallbackToTerminal = {
            // Launch Services couldn't (or silently didn't) run the script —
            // force Terminal.app, which still has the file: the script only
            // self-deletes when executed. One shot, so the async error path
            // and the watchdog can't both fire.
            guard !fellBack else { return }
            fellBack = true
            launchViaOpen(
                arguments: ["-b", "com.apple.Terminal", scriptURL.path],
                appName: "Terminal",
                onFailure: onFailure
            )
        }
        if let bundleID = preferred.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open([scriptURL], withApplicationAt: appURL, configuration: .init()) { _, error in
                guard error != nil else { return }
                Task { @MainActor in fallbackToTerminal() }
            }
        } else if !NSWorkspace.shared.open(scriptURL) {
            fallbackToTerminal()
        }
        // Watchdog: `open` can report success yet never execute the script
        // (observed with a generic open while Terminal was cold). The script
        // deletes itself on execution, so "still on disk" means "never ran".
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if FileManager.default.fileExists(atPath: scriptURL.path) {
                fallbackToTerminal()
            }
        }
    }

    /// Removes leftover scripts from sessions that never launched (the script
    /// normally deletes itself on run). Called once at app startup.
    static func sweepStaleScripts() {
        let dir = scriptsDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.pathExtension == "command" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Internals

    private static var scriptsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ContainerUI-consoles", isDirectory: true)
    }

    private static func writeScript(containerPath: String, id: String, name: String) throws -> URL {
        let dir = scriptsDirectory
        let url = dir.appendingPathComponent(TerminalLauncher.scriptFilename(name: name, id: id))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let body = TerminalLauncher.commandFileBody(containerPath: containerPath, id: id, name: name)
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            throw ConsoleError.scriptWriteFailed(underlying: error)
        }
        return url
    }

    /// Runs `/usr/bin/open` and reports a nonzero exit (e.g. Launch Services
    /// rejecting the bundle) as a failure — `open` exits promptly, so waiting
    /// off the main actor and hopping back is cheap.
    private static func launchViaOpen(
        arguments: [String],
        appName: String,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        // Set before run(): a handler attached after a fast exit never fires.
        process.terminationHandler = { process in
            guard process.terminationStatus != 0 else { return }
            Task { @MainActor in
                onFailure(ConsoleError.launchFailed(app: appName).localizedDescription)
            }
        }
        do {
            try process.run()
        } catch {
            onFailure(ConsoleError.launchFailed(app: appName).localizedDescription)
        }
    }
}
