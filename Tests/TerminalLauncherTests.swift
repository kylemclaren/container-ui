import Foundation
import Testing

/// Verifies the console launcher's pure builders: shell quoting, the exec
/// argv, the `.command` bootstrap body, and per-terminal launch arguments.
@Suite("Terminal launcher")
struct TerminalLauncherTests {

    // MARK: Quoting

    @Test func quotesPlainString() {
        #expect(TerminalLauncher.shellQuote("web") == "'web'")
    }

    @Test func quotesEmbeddedSingleQuote() {
        #expect(TerminalLauncher.shellQuote("a'b") == "'a'\\''b'")
    }

    @Test func quotesSpacesAndMetacharacters() {
        #expect(TerminalLauncher.shellQuote("/My Apps/container; rm -rf $HOME")
                == "'/My Apps/container; rm -rf $HOME'")
    }

    // MARK: Exec argv

    @Test func execArgvShape() {
        let argv = TerminalLauncher.execArgv(containerPath: "/usr/local/bin/container", id: "web")
        #expect(argv == [
            "/usr/local/bin/container", "exec", "-i", "-t", "web",
            "sh", "-c", TerminalLauncher.containerShellScript(),
        ])
    }

    @Test func shellScriptPrefersBashFallsBackToSh() {
        let script = TerminalLauncher.containerShellScript()
        #expect(script.contains("command -v bash"))
        #expect(script.contains("exec bash"))
        #expect(script.contains("exec sh"))
    }

    // MARK: .command body

    @Test func commandFileBodyStructure() {
        let body = TerminalLauncher.commandFileBody(
            containerPath: "/usr/local/bin/container", id: "a1b2c3d4e5f6789", name: "web"
        )
        let lines = body.split(separator: "\n").map(String.init)
        #expect(lines[0] == "#!/bin/sh")
        #expect(lines[1] == "rm -f -- \"$0\"")           // self-deletes before exec
        #expect(lines.last?.hasPrefix("exec ") == true)
        #expect(body.contains("'container · web'"))       // window title
        #expect(body.contains("(a1b2c3d4e5f6)"))          // id truncated to 12
        #expect(body.contains("'/usr/local/bin/container' 'exec' '-i' '-t' 'a1b2c3d4e5f6789'"))
    }

    @Test func commandFileBodyQuotesHostilePath() {
        let body = TerminalLauncher.commandFileBody(
            containerPath: "/My Apps/con'tainer", id: "web", name: "web"
        )
        // Path with a space and a single quote survives POSIX quoting.
        #expect(body.contains("exec '/My Apps/con'\\''tainer' 'exec'"))
    }

    @Test func commandFileBodyStripsControlCharactersFromName() {
        let body = TerminalLauncher.commandFileBody(
            containerPath: "/usr/local/bin/container", id: "web", name: "we\u{07}b\u{1B}]2;pwned"
        )
        // BEL/ESC would terminate or corrupt the OSC title sequence.
        #expect(!body.contains("\u{07}b"))
        #expect(!body.contains("\u{1B}]2;"))
    }

    @Test func commandFileBodyNeverInterpolatesIntoPrintfFormat() {
        // %-heavy, quote-heavy, newline-bearing name: must land only inside
        // single-quoted printf ARGUMENTS ('%s' formats), never in a format
        // string, and never terminate its quoting.
        let hostile = "%s%n '\"; rm -rf /\nowned"
        let body = TerminalLauncher.commandFileBody(
            containerPath: "/usr/local/bin/container", id: "web", name: hostile
        )
        for line in body.split(separator: "\n").map(String.init) where line.hasPrefix("printf ") {
            // Every printf keeps its literal '%s'-style format as the first
            // argument; the hostile value arrives as a later quoted argument.
            #expect(line.hasPrefix("printf '\\033]0;%s\\007' ") || line.hasPrefix("printf '%s\\n' "))
        }
        // Sanity: the body is still a well-formed script ending in exec.
        #expect(body.split(separator: "\n").last?.hasPrefix("exec ") == true)
    }

    // MARK: Per-terminal launch arguments

    @Test func scriptTerminalsUseTheCommandFile() {
        let argv = ["c", "exec", "-i", "-t", "web", "sh", "-c", "x"]
        for app in [TerminalApp.systemDefault, .terminal, .iterm, .warp] {
            #expect(TerminalLauncher.terminalArguments(for: app, execArgv: argv) == nil)
        }
    }

    @Test func argvTerminalArguments() {
        let argv = ["c", "exec", "-i", "-t", "web", "sh", "-c", "x"]
        #expect(TerminalLauncher.terminalArguments(for: .ghostty, execArgv: argv) == ["-e"] + argv)
        #expect(TerminalLauncher.terminalArguments(for: .alacritty, execArgv: argv) == ["-e"] + argv)
        #expect(TerminalLauncher.terminalArguments(for: .kitty, execArgv: argv) == argv)
        #expect(TerminalLauncher.terminalArguments(for: .wezterm, execArgv: argv) == ["start", "--"] + argv)
    }

    // MARK: Script filename

    @Test func filenameUsesSanitizedName() {
        #expect(TerminalLauncher.scriptFilename(name: "my web app", id: "a1b2") == "my-web-app.command")
    }

    @Test func filenameFallsBackToIDWhenNameIsAllHostile() {
        #expect(TerminalLauncher.scriptFilename(name: "///", id: "a1b2c3d4e5f6789") == "a1b2c3d4e5f6.command")
    }
}
