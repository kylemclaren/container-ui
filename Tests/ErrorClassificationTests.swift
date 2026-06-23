import Foundation
import Testing

@Suite("Error classification")
struct ErrorClassificationTests {
    private func result(stderr: String, exit: Int32) -> CommandResult {
        CommandResult(standardOutput: Data(), standardError: Data(stderr.utf8), exitCode: exit)
    }

    @Test func xpcFailureIsDaemonDown() {
        let error = CLIError.classify(result(stderr: "Error: XPC connection error: Connection invalid", exit: 1))
        guard case .daemonNotRunning = error else { Issue.record("got \(error)"); return }
        #expect(error.isBackendUnavailable)
    }

    @Test func startHintIsDaemonDown() {
        let error = CLIError.classify(result(stderr: "Ensure container system service has been started with `container system start`.", exit: 1))
        guard case .daemonNotRunning = error else { Issue.record("got \(error)"); return }
    }

    @Test func notFoundIsClassified() {
        let error = CLIError.classify(result(stderr: "notFound: \"no such container: web\"", exit: 1))
        guard case .notFound = error else { Issue.record("got \(error)"); return }
        #expect(!error.isBackendUnavailable)
    }

    @Test func usageExitCode() {
        let error = CLIError.classify(result(stderr: "Usage: container ...", exit: 64))
        guard case .usage = error else { Issue.record("got \(error)"); return }
    }

    @Test func genericFailure() {
        let error = CLIError.classify(result(stderr: "something broke", exit: 2))
        guard case .commandFailed(let code, _) = error else { Issue.record("got \(error)"); return }
        #expect(code == 2)
    }

    @Test func executableNotFoundIsBackendUnavailable() {
        #expect(CLIError.executableNotFound(searched: []).isBackendUnavailable)
        #expect(CLIError.launchFailed(path: "/x", message: "no").isBackendUnavailable)
    }
}
