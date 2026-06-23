import Foundation

/// A `CommandRunner` test double that returns programmed results and records the
/// invocations it received, so services can be tested without a live backend.
final class MockCommandRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _invocations: [CommandInvocation] = []

    var responder: @Sendable (CommandInvocation) -> CommandResult
    var streamLines: [StreamLine] = []
    var streamError: Error?

    init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        let result = CommandResult(
            standardOutput: Data(stdout.utf8),
            standardError: Data(stderr.utf8),
            exitCode: exitCode
        )
        self.responder = { _ in result }
    }

    init(responder: @escaping @Sendable (CommandInvocation) -> CommandResult) {
        self.responder = responder
    }

    var invocations: [CommandInvocation] {
        lock.lock(); defer { lock.unlock() }
        return _invocations
    }

    var lastArguments: [String]? {
        lock.lock(); defer { lock.unlock() }
        return _invocations.last?.arguments
    }

    func run(_ invocation: CommandInvocation) async throws -> CommandResult {
        lock.lock(); _invocations.append(invocation); lock.unlock()
        return responder(invocation)
    }

    func stream(_ invocation: CommandInvocation) -> AsyncThrowingStream<StreamLine, Error> {
        lock.lock(); _invocations.append(invocation); lock.unlock()
        let lines = streamLines
        let error = streamError
        return AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            if let error { continuation.finish(throwing: error) } else { continuation.finish() }
        }
    }
}

extension ContainerCLI {
    /// Builds a CLI wired to a mock runner with a dummy executable path.
    static func mock(_ runner: MockCommandRunner) -> ContainerCLI {
        ContainerCLI(executableURL: URL(fileURLWithPath: "/usr/local/bin/container"), runner: runner)
    }
}
