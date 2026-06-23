import Foundation

/// Thin façade around a `CommandRunner` that knows how to invoke the `container`
/// binary, classify failures, and decode its JSON output.
///
/// All `container` JSON is produced by a plain `JSONEncoder` with
/// `dateEncodingStrategy = .iso8601` and **no** key strategy, so we mirror that
/// on the decode side. Optional fields are *omitted* (never `null`) when absent.
struct ContainerCLI: Sendable {
    var executableURL: URL
    var runner: CommandRunner

    init(executableURL: URL, runner: CommandRunner = ProcessCommandRunner()) {
        self.executableURL = executableURL
        self.runner = runner
    }

    /// Shared decoder configured to match the CLI's encoder.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func invocation(_ arguments: [String], stdin: Data? = nil) -> CommandInvocation {
        CommandInvocation(executableURL: executableURL, arguments: arguments, standardInput: stdin)
    }

    /// Runs the command to completion without interpreting its exit code.
    @discardableResult
    func run(_ arguments: [String], stdin: Data? = nil) async throws -> CommandResult {
        try await runner.run(invocation(arguments, stdin: stdin))
    }

    /// Runs the command, requiring exit 0; returns raw stdout bytes.
    func output(_ arguments: [String], stdin: Data? = nil) async throws -> Data {
        let result = try await run(arguments, stdin: stdin)
        guard result.isSuccess else { throw CLIError.classify(result) }
        return result.standardOutput
    }

    /// Runs the command, requiring exit 0; returns trimmed stdout text.
    @discardableResult
    func text(_ arguments: [String], stdin: Data? = nil) async throws -> String {
        let data = try await output(arguments, stdin: stdin)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs the command, requiring exit 0; decodes stdout as JSON.
    func decode<T: Decodable>(_ type: T.Type, from arguments: [String]) async throws -> T {
        let data = try await output(arguments)
        return try Self.decodeJSON(T.self, from: data)
    }

    /// Decodes JSON using the CLI-matched decoder, mapping failures to `CLIError`.
    static func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CLIError.decodingFailed(message: String(describing: error))
        }
    }

    /// Streams a long-lived command (logs follow, pull progress) line-by-line.
    func stream(_ arguments: [String]) -> AsyncThrowingStream<StreamLine, Error> {
        runner.stream(invocation(arguments))
    }
}
