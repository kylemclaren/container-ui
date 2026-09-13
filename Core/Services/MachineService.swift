import Foundation

/// Options for `container machine create`, mapped to its flags.
struct MachineCreateOptions: Sendable, Equatable {
    var image: String
    var name: String?
    var cpus: Int?
    var memory: String?              // e.g. "4G"
    var homeMount: MachineHomeMount?
    var setDefault: Bool = false
}

/// Settings accepted by `container machine set` as `key=value` pairs. Nil
/// fields are left untouched. Changes land on disk immediately and take effect
/// on the machine's next boot.
struct MachineSettings: Sendable, Equatable {
    var cpus: Int?
    var memory: String?
    var homeMount: MachineHomeMount?
    var virtualization: Bool?
    /// An empty string resets to the system default kernel.
    var kernel: String?

    var isEmpty: Bool { arguments.isEmpty }

    var arguments: [String] {
        var out: [String] = []
        if let cpus { out.append("cpus=\(cpus)") }
        if let memory, !memory.isEmpty { out.append("memory=\(memory)") }
        if let homeMount { out.append("home-mount=\(homeMount.rawValue)") }
        if let virtualization { out.append("virtualization=\(virtualization)") }
        if let kernel { out.append("kernel=\(kernel)") }
        return out
    }
}

/// Container machine management, backed by the `container machine …` CLI
/// subcommands (available since container 1.0.0).
struct MachineService: Sendable {
    let cli: ContainerCLI

    init(cli: ContainerCLI) { self.cli = cli }

    // MARK: Argument builders (pure, unit-tested)

    static func listArguments() -> [String] {
        ["machine", "list", "--format", "json"]
    }

    static func inspectArguments(id: String) -> [String] {
        ["machine", "inspect", id]
    }

    static func createArguments(_ options: MachineCreateOptions) -> [String] {
        // `--progress plain` gives line-oriented output we can stream.
        var args = ["machine", "create", "--progress", "plain"]
        if let name = options.name, !name.isEmpty { args += ["--name", name] }
        if let cpus = options.cpus { args += ["--cpus", String(cpus)] }
        if let memory = options.memory, !memory.isEmpty { args += ["--memory", memory] }
        if let homeMount = options.homeMount { args += ["--home-mount", homeMount.rawValue] }
        if options.setDefault { args.append("--set-default") }
        args.append(options.image)
        return args
    }

    /// There is no `machine start`. `run --detach` boots the machine when it's
    /// stopped and runs a trivial command without attaching a terminal.
    static func startArguments(id: String) -> [String] {
        ["machine", "run", "--name", id, "--detach", "--", "true"]
    }

    static func stopArguments(id: String) -> [String] {
        ["machine", "stop", id]
    }

    static func deleteArguments(id: String) -> [String] {
        ["machine", "delete", id]
    }

    static func setDefaultArguments(id: String) -> [String] {
        ["machine", "set-default", id]
    }

    static func setArguments(id: String, settings: MachineSettings) -> [String] {
        ["machine", "set", "--name", id] + settings.arguments
    }

    static func logsArguments(id: String, follow: Bool, tail: Int?, boot: Bool) -> [String] {
        var args = ["machine", "logs"]
        if boot { args.append("--boot") }
        if let tail { args += ["-n", String(tail)] }
        if follow { args.append("--follow") }
        return args + [id]
    }

    /// The interactive login shell as the host user, home directory mounted.
    /// Boots the machine first if it's stopped. Needs a TTY — this is what the
    /// terminal launcher runs.
    static func shellArguments(id: String) -> [String] {
        ["machine", "run", "--name", id]
    }

    // MARK: Validation & formatting

    /// Mirrors the CLI's `ManagedContainer.nameValid`: at most 63 characters,
    /// an alphanumeric first character, then letters, digits, `_`, `.`, `-`.
    static func isValidName(_ name: String) -> Bool {
        guard name.count <= 63 else { return false }
        return name.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9_.-]+$"#, options: .regularExpression) != nil
    }

    /// Renders a byte count in the CLI's memory-flag syntax (`8G`, `1536M`) so
    /// settings can be pre-filled from `inspect` output.
    static func memoryFlag(fromBytes bytes: UInt64) -> String {
        let gib: UInt64 = 1 << 30
        let mib: UInt64 = 1 << 20
        if bytes >= gib, bytes % gib == 0 { return "\(bytes / gib)G" }
        return "\(max(1, bytes / mib))M"
    }

    /// A machine created with `--no-boot` from the CLI hasn't run its
    /// first-boot user setup, which the headless start can't drive (it needs a
    /// terminal). Point at the shell action, which boots interactively.
    static func startErrorMessage(_ error: CLIError) -> String {
        let text = error.localizedDescription
        let lower = text.lowercased()
        if lower.contains("tty") || lower.contains("terminal") || lower.contains("not supported by device") {
            return "This machine still needs its first-boot setup, which runs in a terminal. Use Open shell to boot it interactively."
        }
        return text
    }

    // MARK: Operations

    func list() async throws -> [ContainerMachine] {
        try await cli.decode([ContainerMachine].self, from: Self.listArguments())
    }

    func inspect(id: String) async throws -> MachineDetail? {
        try await cli.decode([MachineDetail].self, from: Self.inspectArguments(id: id)).first
    }

    /// Creates and boots a machine, streaming the CLI's progress lines.
    func create(_ options: MachineCreateOptions) -> AsyncThrowingStream<StreamLine, Error> {
        cli.stream(Self.createArguments(options))
    }

    @discardableResult
    func start(id: String) async throws -> String {
        try await cli.text(Self.startArguments(id: id))
    }

    @discardableResult
    func stop(id: String) async throws -> String {
        try await cli.text(Self.stopArguments(id: id))
    }

    @discardableResult
    func delete(id: String) async throws -> String {
        try await cli.text(Self.deleteArguments(id: id))
    }

    @discardableResult
    func setDefault(id: String) async throws -> String {
        try await cli.text(Self.setDefaultArguments(id: id))
    }

    @discardableResult
    func set(id: String, settings: MachineSettings) async throws -> String {
        try await cli.text(Self.setArguments(id: id, settings: settings))
    }

    /// One-shot log fetch (no follow).
    func logs(id: String, tail: Int? = nil, boot: Bool = false) async throws -> String {
        try await cli.text(Self.logsArguments(id: id, follow: false, tail: tail, boot: boot))
    }

    /// Live, followed logs as a line stream.
    func streamLogs(id: String, tail: Int? = nil, boot: Bool = false) -> AsyncThrowingStream<StreamLine, Error> {
        cli.stream(Self.logsArguments(id: id, follow: true, tail: tail, boot: boot))
    }
}
