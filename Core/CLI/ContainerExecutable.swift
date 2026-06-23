import Foundation

/// Locates the `container` CLI binary. GUI apps don't inherit the user's shell
/// `PATH`, so we probe the known install location first and let the user
/// override the path in Settings.
enum ContainerExecutable {
    /// Where the signed installer places the CLI.
    static let defaultInstallPath = "/usr/local/bin/container"

    /// Directories probed (in order) when no explicit override is given.
    static let searchDirectories = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin"]

    static var searchedPaths: [String] {
        [defaultInstallPath] + searchDirectories
            .filter { $0 != "/usr/local/bin" }
            .map { $0 + "/container" }
    }

    /// Resolves the executable URL, honoring an explicit override first.
    /// - Parameter override: a user-provided absolute path, or nil.
    /// - Returns: the resolved URL, or nil if nothing executable was found.
    static func resolve(override: String?, fileManager: FileManager = .default) -> URL? {
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            let path = (override as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        for directory in searchDirectories {
            let candidate = directory + "/container"
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}
