import Foundation

/// A single child-process invocation: which executable, with which arguments,
/// optional environment overrides, and optional data to pipe to stdin.
struct CommandInvocation: Sendable, Equatable {
    var executableURL: URL
    var arguments: [String]
    var environment: [String: String]?
    var standardInput: Data?

    init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        standardInput: Data? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.standardInput = standardInput
    }
}

/// The buffered result of running a command to completion.
struct CommandResult: Sendable, Equatable {
    var standardOutput: Data
    var standardError: Data
    var exitCode: Int32

    init(standardOutput: Data, standardError: Data, exitCode: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }

    var standardOutputString: String { String(decoding: standardOutput, as: UTF8.self) }
    var standardErrorString: String { String(decoding: standardError, as: UTF8.self) }
    var isSuccess: Bool { exitCode == 0 }
}

/// A single line emitted by a streaming command, tagged by its origin stream.
enum StreamLine: Sendable, Equatable {
    case standardOutput(String)
    case standardError(String)

    var text: String {
        switch self {
        case .standardOutput(let s), .standardError(let s): return s
        }
    }
}

/// Abstraction over process execution so services can be unit-tested against
/// recorded fixtures without a live `container` backend.
protocol CommandRunner: Sendable {
    /// Runs the command to completion, buffering stdout/stderr.
    func run(_ invocation: CommandInvocation) async throws -> CommandResult
    /// Runs the command and yields output line-by-line until it exits.
    /// Finishes with a `CLIError` if the process exits non-zero.
    func stream(_ invocation: CommandInvocation) -> AsyncThrowingStream<StreamLine, Error>
}

// MARK: - Real implementation

/// `CommandRunner` backed by Foundation's `Process`.
struct ProcessCommandRunner: CommandRunner {
    init() {}

    func run(_ invocation: CommandInvocation) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, Error>) in
            // Everything below runs on a background queue; blocking here is fine
            // and keeps us off the cooperative thread pool / main actor.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = invocation.executableURL
                process.arguments = invocation.arguments
                process.environment = Self.resolvedEnvironment(invocation.environment)

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                let inPipe: Pipe? = invocation.standardInput != nil ? Pipe() : nil
                if let inPipe { process.standardInput = inPipe }

                // Drain stdout and stderr concurrently to avoid pipe-buffer deadlock.
                let outBox = DataBox()
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outBox.set((try? outPipe.fileHandleForReading.readToEnd()) ?? Data())
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errBox.set((try? errPipe.fileHandleForReading.readToEnd()) ?? Data())
                    group.leave()
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(
                        throwing: CLIError.launchFailed(
                            path: invocation.executableURL.path,
                            message: error.localizedDescription
                        )
                    )
                    return
                }

                if let stdin = invocation.standardInput, let inPipe {
                    try? inPipe.fileHandleForWriting.write(contentsOf: stdin)
                    try? inPipe.fileHandleForWriting.close()
                }

                process.waitUntilExit()
                group.wait()
                continuation.resume(
                    returning: CommandResult(
                        standardOutput: outBox.get(),
                        standardError: errBox.get(),
                        exitCode: process.terminationStatus
                    )
                )
            }
        }
    }

    func stream(_ invocation: CommandInvocation) -> AsyncThrowingStream<StreamLine, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = invocation.executableURL
            process.arguments = invocation.arguments
            process.environment = Self.resolvedEnvironment(invocation.environment)

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let outBuffer = LineBuffer { continuation.yield(.standardOutput($0)) }
            let errBuffer = LineBuffer { continuation.yield(.standardError($0)) }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    outBuffer.flush()
                } else {
                    outBuffer.append(data)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    errBuffer.flush()
                } else {
                    errBuffer.append(data)
                }
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                outBuffer.flush()
                errBuffer.flush()
                if proc.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(
                        throwing: CLIError.commandFailed(
                            code: proc.terminationStatus,
                            stderr: errBuffer.collected.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                }
            }

            continuation.onTermination = { _ in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(
                    throwing: CLIError.launchFailed(
                        path: invocation.executableURL.path,
                        message: error.localizedDescription
                    )
                )
            }
        }
    }

    /// GUI apps launched from Finder inherit a minimal `PATH`, so make sure the
    /// usual install locations are present for the `container` CLI and any helper
    /// tools it shells out to.
    static func resolvedEnvironment(_ overrides: [String: String]?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var parts = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"] where !parts.contains(dir) {
            parts.append(dir)
        }
        env["PATH"] = parts.joined(separator: ":")
        if let overrides {
            for (key, value) in overrides { env[key] = value }
        }
        return env
    }
}

// MARK: - Private helpers

/// Thread-safe one-shot data holder used to collect a pipe's contents.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()
    func set(_ data: Data) { lock.lock(); value = data; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return value }
}

/// Accumulates streamed bytes and emits complete, newline-delimited lines,
/// holding back any trailing partial line until more data arrives or `flush()`.
final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let onLine: @Sendable (String) -> Void
    private var pending = ""
    private(set) var collected = ""

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        collected += chunk
        pending += chunk
        var lines = pending.components(separatedBy: "\n")
        pending = lines.removeLast()
        lock.unlock()
        for line in lines { onLine(line) }
    }

    func flush() {
        lock.lock()
        let remaining = pending
        pending = ""
        lock.unlock()
        if !remaining.isEmpty { onLine(remaining) }
    }
}
