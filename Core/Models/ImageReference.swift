import Foundation

/// A parsed OCI image reference, split into registry / repository / tag / digest.
///
/// Examples:
/// - `docker.io/library/alpine:latest` → registry `docker.io`, repository
///   `library/alpine`, tag `latest`
/// - `nginx` → repository `nginx`, tag nil
/// - `localhost:5000/app:1.0` → registry `localhost:5000`, repository `app`
/// - `ubuntu@sha256:abc…` → repository `ubuntu`, digest `sha256:abc…`
struct ImageReference: Equatable, Sendable {
    var registry: String?
    var repository: String
    var tag: String?
    var digest: String?

    /// The repository's last path component, e.g. `alpine` from `library/alpine`.
    var name: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }

    /// A compact display string: `name:tag` (or `name@digest`, or just `name`).
    var displayName: String {
        if let tag { return "\(name):\(tag)" }
        if let digest { return "\(name)@\(String(digest.prefix(19)))…" }
        return name
    }

    static func parse(_ reference: String) -> ImageReference {
        var remainder = reference
        var digest: String?

        // Digest (`@sha256:...`) takes precedence over a tag.
        if let atIndex = remainder.firstIndex(of: "@") {
            digest = String(remainder[remainder.index(after: atIndex)...])
            remainder = String(remainder[..<atIndex])
        }

        // Split registry from path. The first segment is a registry only if it
        // looks like a host (contains a dot or colon, or is "localhost").
        var registry: String?
        var path = remainder
        if let slashIndex = remainder.firstIndex(of: "/") {
            let first = String(remainder[..<slashIndex])
            if first == "localhost" || first.contains(".") || first.contains(":") {
                registry = first
                path = String(remainder[remainder.index(after: slashIndex)...])
            }
        }

        // A tag is a `:` in the final path component only.
        var tag: String?
        var repository = path
        if digest == nil, let colonIndex = path.lastIndex(of: ":") {
            let afterColon = path[path.index(after: colonIndex)...]
            if !afterColon.contains("/") {
                tag = String(afterColon)
                repository = String(path[..<colonIndex])
            }
        }

        return ImageReference(registry: registry, repository: repository, tag: tag, digest: digest)
    }

    /// The host's normalized architecture string as the CLI would report it.
    static var hostArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "amd64"
        #else
        return "arm64"
        #endif
    }
}
