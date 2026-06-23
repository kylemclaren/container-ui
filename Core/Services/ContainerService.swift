import Foundation

/// Options for creating/running a container, mapped to `container run` flags.
struct RunOptions: Sendable, Equatable {
    var image: String
    var name: String?
    var detach: Bool = true
    var remove: Bool = false
    var interactive: Bool = false
    var tty: Bool = false
    var env: [String] = []           // KEY=VALUE
    var publishPorts: [String] = []  // [host-ip:]host-port:container-port[/proto]
    var volumes: [String] = []       // source:target[,ro]
    var cpus: Int?
    var memory: String?              // e.g. "1G"
    var command: [String] = []
}

/// Container lifecycle and inspection, backed by the `container` CLI.
struct ContainerService: Sendable {
    let cli: ContainerCLI

    init(cli: ContainerCLI) { self.cli = cli }

    // MARK: Argument builders (pure, unit-tested)

    static func listArguments(all: Bool) -> [String] {
        all ? ["list", "--all", "--format", "json"] : ["list", "--format", "json"]
    }

    static func inspectArguments(id: String) -> [String] {
        ["inspect", id]
    }

    static func statsArguments(ids: [String]) -> [String] {
        ["stats", "--no-stream", "--format", "json"] + ids
    }

    static func startArguments(id: String) -> [String] {
        ["start", id]
    }

    static func stopArguments(ids: [String], time: Int? = nil, signal: String? = nil) -> [String] {
        var args = ["stop"]
        if let time { args += ["--time", String(time)] }
        if let signal { args += ["--signal", signal] }
        return args + ids
    }

    static func killArguments(ids: [String], signal: String? = nil) -> [String] {
        var args = ["kill"]
        if let signal { args += ["--signal", signal] }
        return args + ids
    }

    static func deleteArguments(ids: [String], force: Bool) -> [String] {
        ["delete"] + (force ? ["--force"] : []) + ids
    }

    static func logsArguments(id: String, follow: Bool, tail: Int?, boot: Bool) -> [String] {
        var args = ["logs"]
        if boot { args.append("--boot") }
        if let tail { args += ["-n", String(tail)] }
        if follow { args.append("--follow") }
        return args + [id]
    }

    static func execArguments(id: String, command: [String], interactive: Bool = false, tty: Bool = false) -> [String] {
        var args = ["exec"]
        if interactive { args.append("-i") }
        if tty { args.append("-t") }
        return args + [id] + command
    }

    static func runArguments(_ options: RunOptions) -> [String] {
        var args = ["run"]
        if options.detach { args.append("--detach") }
        if options.remove { args.append("--rm") }
        if options.interactive { args.append("-i") }
        if options.tty { args.append("-t") }
        if let name = options.name, !name.isEmpty { args += ["--name", name] }
        for value in options.env { args += ["--env", value] }
        for value in options.publishPorts { args += ["--publish", value] }
        for value in options.volumes { args += ["--volume", value] }
        if let cpus = options.cpus { args += ["--cpus", String(cpus)] }
        if let memory = options.memory, !memory.isEmpty { args += ["--memory", memory] }
        args.append(options.image)
        args += options.command
        return args
    }

    // MARK: Operations

    func list(all: Bool = true) async throws -> [Container] {
        try await cli.decode([Container].self, from: Self.listArguments(all: all))
    }

    func inspect(id: String) async throws -> Container? {
        try await cli.decode([Container].self, from: Self.inspectArguments(id: id)).first
    }

    func stats(ids: [String] = []) async throws -> [ContainerStats] {
        try await cli.decode([ContainerStats].self, from: Self.statsArguments(ids: ids))
    }

    @discardableResult
    func start(id: String) async throws -> String {
        try await cli.text(Self.startArguments(id: id))
    }

    @discardableResult
    func stop(ids: [String], time: Int? = nil, signal: String? = nil) async throws -> String {
        try await cli.text(Self.stopArguments(ids: ids, time: time, signal: signal))
    }

    @discardableResult
    func kill(ids: [String], signal: String? = nil) async throws -> String {
        try await cli.text(Self.killArguments(ids: ids, signal: signal))
    }

    @discardableResult
    func delete(ids: [String], force: Bool = false) async throws -> String {
        try await cli.text(Self.deleteArguments(ids: ids, force: force))
    }

    /// Stop then start a single container.
    func restart(id: String, time: Int? = nil) async throws {
        _ = try await stop(ids: [id], time: time)
        _ = try await start(id: id)
    }

    /// One-shot log fetch (no follow).
    func logs(id: String, tail: Int? = nil, boot: Bool = false) async throws -> String {
        try await cli.text(Self.logsArguments(id: id, follow: false, tail: tail, boot: boot))
    }

    /// Live, followed logs as a line stream.
    func streamLogs(id: String, tail: Int? = nil, boot: Bool = false) -> AsyncThrowingStream<StreamLine, Error> {
        cli.stream(Self.logsArguments(id: id, follow: true, tail: tail, boot: boot))
    }

    /// One-shot command execution inside a running container (captures output).
    @discardableResult
    func exec(id: String, command: [String]) async throws -> String {
        try await cli.text(Self.execArguments(id: id, command: command))
    }

    /// Runs a new container. When detached, returns the new container id.
    @discardableResult
    func run(_ options: RunOptions) async throws -> String {
        try await cli.text(Self.runArguments(options))
    }
}
