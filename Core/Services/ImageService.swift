import Foundation

/// Options for `container build`, mapped to its flags.
///
/// Note: `build` is a *top-level* `container` subcommand (not `container image
/// build`), but it produces an image, so it's surfaced here alongside the other
/// image operations.
struct BuildOptions: Sendable, Equatable {
    var contextDirectory: String     // positional build context (a directory)
    var tag: String?                 // -t/--tag — name for the built image
    var dockerfilePath: String?      // -f/--file — path to Dockerfile
    var buildArgs: [String] = []     // --build-arg KEY=VALUE (repeatable)
    var labels: [String] = []        // --label KEY=VALUE (repeatable)
    var noCache: Bool = false        // --no-cache
    var target: String?              // --target <stage>
}

/// Image management, backed by the `container image …` CLI subcommands
/// (plus the top-level `container build`).
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

    static func pruneArguments() -> [String] {
        ["image", "prune"]
    }

    static func buildArguments(_ options: BuildOptions) -> [String] {
        // `--progress plain` gives line-oriented output we can stream/parse,
        // matching how `pull` streams.
        var args = ["build", "--progress", "plain"]
        if let tag = options.tag, !tag.isEmpty { args += ["--tag", tag] }
        if let file = options.dockerfilePath, !file.isEmpty { args += ["--file", file] }
        for value in options.buildArgs { args += ["--build-arg", value] }
        for value in options.labels { args += ["--label", value] }
        if options.noCache { args.append("--no-cache") }
        if let target = options.target, !target.isEmpty { args += ["--target", target] }
        args.append(options.contextDirectory)
        return args
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

    /// Builds an image from a Dockerfile, streaming BuildKit progress lines.
    func build(_ options: BuildOptions) -> AsyncThrowingStream<StreamLine, Error> {
        cli.stream(Self.buildArguments(options))
    }

    @discardableResult
    func delete(references: [String], force: Bool = false) async throws -> String {
        try await cli.text(Self.deleteArguments(references: references, force: force))
    }

    @discardableResult
    func tag(source: String, target: String) async throws -> String {
        try await cli.text(Self.tagArguments(source: source, target: target))
    }

    /// Removes dangling and unreferenced images.
    @discardableResult
    func prune() async throws -> String {
        try await cli.text(Self.pruneArguments())
    }
}
