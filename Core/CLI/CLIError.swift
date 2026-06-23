import Foundation

/// Typed errors surfaced from the `container` CLI, classified from exit codes
/// and stderr so the UI can show actionable messages (and special-case a
/// backend that isn't running).
enum CLIError: Error, Sendable, Equatable {
    /// The `container` binary could not be located.
    case executableNotFound(searched: [String])
    /// The process could not be launched at all.
    case launchFailed(path: String, message: String)
    /// The apiserver / system service is not running.
    case daemonNotRunning(message: String)
    /// A referenced container/image/etc. does not exist.
    case notFound(message: String)
    /// Argument-parser usage/validation failure (exit 64).
    case usage(message: String)
    /// Generic non-zero exit.
    case commandFailed(code: Int32, stderr: String)
    /// stdout could not be decoded into the expected shape.
    case decodingFailed(message: String)

    /// Classifies a finished, non-zero `CommandResult` into a specific case.
    static func classify(_ result: CommandResult) -> CLIError {
        let stderr = result.standardErrorString.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = stderr.lowercased()

        // The CLI rewraps "daemon down" XPC failures with a hint to run
        // `container system start`; system status reports "not running".
        if lower.contains("xpc connection")
            || lower.contains("container system start")
            || lower.contains("ensure container system service")
            || lower.contains("apiserver is not running") {
            return .daemonNotRunning(message: stderr)
        }
        // ContainerizationError surfaces as `notFound: "no such container: x"`.
        if lower.contains("not found") || lower.contains("no such") {
            return .notFound(message: stderr)
        }
        if result.exitCode == 64 {
            return .usage(message: stderr)
        }
        return .commandFailed(code: result.exitCode, stderr: stderr)
    }
}

extension CLIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Couldn’t find the container command-line tool."
        case .launchFailed(let path, let message):
            return "Couldn’t launch \(path): \(message)"
        case .daemonNotRunning:
            return "The container system service isn’t running."
        case .notFound(let message):
            return message.isEmpty ? "Not found." : message
        case .usage(let message):
            return message.isEmpty ? "Invalid arguments." : message
        case .commandFailed(let code, let stderr):
            return stderr.isEmpty ? "Command failed (exit \(code))." : stderr
        case .decodingFailed:
            return "Couldn’t read the response from the container tool."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .executableNotFound(let searched):
            return "Install Apple’s container tool, or set its path in Settings. Looked in: \(searched.joined(separator: ", "))."
        case .daemonNotRunning:
            return "Start it from the System tab, or run `container system start` in Terminal."
        default:
            return nil
        }
    }

    /// Whether this error means the backend is unreachable (used to drive the
    /// global "backend down" UI state).
    var isBackendUnavailable: Bool {
        switch self {
        case .daemonNotRunning, .executableNotFound, .launchFailed:
            return true
        default:
            return false
        }
    }
}
