import Foundation

/// Terminal applications the console feature knows how to drive.
///
/// Two launch families:
/// - **Script terminals** (`terminalArguments` returns nil): Terminal.app and
///   iTerm2 natively execute `.command` files, so we write a self-deleting
///   bootstrap script and open it — no AppleScript, no Automation TCC prompt.
/// - **Argv terminals**: Ghostty/kitty/Alacritty/WezTerm accept the command as
///   launch arguments (`open -na <App> --args …`), which sidesteps shell
///   quoting entirely.
enum TerminalApp: String, CaseIterable, Identifiable, Sendable {
    /// Opens the `.command` script with whatever app the user has bound to
    /// that file type — Terminal.app unless they've changed it.
    case systemDefault
    case terminal
    case iterm
    case ghostty
    case warp
    case kitty
    case alacritty
    case wezterm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemDefault: return "System default"
        case .terminal: return "Terminal"
        case .iterm: return "iTerm2"
        case .ghostty: return "Ghostty"
        case .warp: return "Warp"
        case .kitty: return "kitty"
        case .alacritty: return "Alacritty"
        case .wezterm: return "WezTerm"
        }
    }

    /// nil for `.systemDefault`, which resolves through Launch Services.
    var bundleIdentifier: String? {
        switch self {
        case .systemDefault: return nil
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        case .warp: return "dev.warp.Warp-Stable"
        case .kitty: return "net.kovidgoyal.kitty"
        case .alacritty: return "org.alacritty"
        case .wezterm: return "com.github.wez.wezterm"
        }
    }
}

/// Pure builders for the one-click container console: the interactive `exec`
/// argv, the `.command` bootstrap script, and per-terminal launch arguments.
/// Effectful launching lives in `ConsoleOpener` (App layer).
enum TerminalLauncher {
    /// Run inside the container: prefer bash, fall back to sh. Works on
    /// bash/dash/busybox images; `exec` keeps the shell as PID of the session.
    static func containerShellScript() -> String {
        "if command -v bash >/dev/null 2>&1; then exec bash; else exec sh; fi"
    }

    /// POSIX single-quote wrapping — safe for any byte except NUL.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The full interactive exec invocation, as an argv array (unquoted).
    static func execArgv(containerPath: String, id: String) -> [String] {
        [containerPath] + ContainerService.execArguments(
            id: id,
            command: ["sh", "-c", containerShellScript()],
            interactive: true,
            tty: true
        )
    }

    /// The self-deleting `.command` bootstrap body. Self-delete at the top is
    /// safe: the interpreting shell already holds the file open, and `exec`
    /// replaces the process so nothing lingers after the session ends.
    static func commandFileBody(containerPath: String, id: String, name: String) -> String {
        let title = sanitizeForDisplay("container · \(name)")
        let header = sanitizeForDisplay("Connecting to \(name) (\(String(id.prefix(12))))…")
        let exec = execArgv(containerPath: containerPath, id: id)
            .map(shellQuote)
            .joined(separator: " ")
        return """
        #!/bin/sh
        rm -f -- "$0"
        printf '\\033]0;%s\\007' \(shellQuote(title))
        printf '%s\\n' \(shellQuote(header))
        exec \(exec)
        """
    }

    /// Launch arguments for an argv terminal, or nil when the app should open
    /// the `.command` script instead (Terminal, iTerm2, Warp, system default).
    static func terminalArguments(for app: TerminalApp, execArgv: [String]) -> [String]? {
        switch app {
        case .systemDefault, .terminal, .iterm, .warp:
            return nil
        case .ghostty, .alacritty:
            return ["-e"] + execArgv
        case .kitty:
            return execArgv
        case .wezterm:
            return ["start", "--"] + execArgv
        }
    }

    /// Script filename — doubles as the Terminal window title fallback, so
    /// lead with the container name. Filesystem-hostile characters stripped.
    static func scriptFilename(name: String, id: String) -> String {
        let safe = name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "-" }
        let base = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return "\(base.isEmpty ? String(id.prefix(12)) : base).command"
    }

    /// Strips control characters (they'd corrupt the OSC title sequence).
    private static func sanitizeForDisplay(_ s: String) -> String {
        String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
    }
}
