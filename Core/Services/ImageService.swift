import Foundation

/// Image management, backed by the `container image …` CLI subcommands.
struct ImageService: Sendable {
    let cli: ContainerCLI

    init(cli: ContainerCLI) { self.cli = cli }

    // MARK: Argument builders (pure, unit-tested)

    static func listArguments() -> [String] {
        ["image", "list", "--format", "json"]
    }

    static func inspectArguments(reference: String) -> [String] {
        ["image", "inspect", reference]
    }

    static func pullArguments(reference: String) -> [String] {
        // `--progress plain` gives line-oriented output we can stream/parse.
        ["image", "pull", "--progress", "plain", reference]
    }

    static func deleteArguments(references: [String], force: Bool) -> [String] {
        ["image", "delete"] + (force ? ["--force"] : []) + references
    }

    static func tagArguments(source: String, target: String) -> [String] {
        ["image", "tag", source, target]
    }

    // MARK: Operations

    func list() async throws -> [ContainerImage] {
        try await cli.decode([ContainerImage].self, from: Self.listArguments())
    }

    func inspect(reference: String) async throws -> ContainerImage? {
        try await cli.decode([ContainerImage].self, from: Self.inspectArguments(reference: reference)).first
    }

    /// Pulls an image, streaming progress lines (mostly on stderr).
    func pull(reference: String) -> AsyncThrowingStream<StreamLine, Error> {
        cli.stream(Self.pullArguments(reference: reference))
    }

    @discardableResult
    func delete(references: [String], force: Bool = false) async throws -> String {
        try await cli.text(Self.deleteArguments(references: references, force: force))
    }

    @discardableResult
    func tag(source: String, target: String) async throws -> String {
        try await cli.text(Self.tagArguments(source: source, target: target))
    }
}
