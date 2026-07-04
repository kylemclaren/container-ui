import Foundation

/// Models for Docker Hub's public HTTP API. `container` has no registry-search
/// command, so these back the one feature that talks to the network directly.
///
/// Docker Hub uses `snake_case` keys (mapped explicitly per model, matching the
/// house rule of never using a key-decoding strategy) and timestamps with
/// nanosecond fractional seconds — which break `.iso8601` — so every date is
/// decoded as a `String` and parsed lazily at the view layer (the same approach
/// `OCIImage.created` takes).

/// One page of repository search results (`GET /v2/search/repositories/`).
struct HubSearchResponse: Codable, Hashable, Sendable {
    var count: Int
    var next: String?
    var previous: String?
    var results: [HubRepository]
}

/// A repository in Docker Hub search results.
struct HubRepository: Codable, Hashable, Sendable, Identifiable {
    /// `nginx` for official images, `owner/repo` for community images.
    var repoName: String
    var shortDescription: String?
    var starCount: Int
    var pullCount: Int
    var repoOwner: String?
    var isOfficial: Bool
    var isAutomated: Bool

    /// `repoName` is globally unique on Hub, so it doubles as the identity.
    var id: String { repoName }

    /// Namespace used by the tags API and the pull reference. Official images
    /// live under `library`; community images carry their owner as the namespace.
    var namespace: String {
        guard let slash = repoName.firstIndex(of: "/") else { return "library" }
        return String(repoName[..<slash])
    }

    /// The bare repository name (`nginx` from `nginx/nginx-ingress`).
    var repository: String {
        guard let slash = repoName.firstIndex(of: "/") else { return repoName }
        return String(repoName[repoName.index(after: slash)...])
    }

    /// Fully-qualified reference for `container image pull`, e.g.
    /// `docker.io/library/nginx:latest`.
    func pullReference(tag: String = "latest") -> String {
        "docker.io/\(namespace)/\(repository):\(tag)"
    }

    private enum CodingKeys: String, CodingKey {
        case repoName = "repo_name"
        case shortDescription = "short_description"
        case starCount = "star_count"
        case pullCount = "pull_count"
        case repoOwner = "repo_owner"
        case isOfficial = "is_official"
        case isAutomated = "is_automated"
    }
}

/// One page of a repository's tags (`GET /v2/repositories/{ns}/{repo}/tags/`).
struct HubTagsResponse: Codable, Hashable, Sendable {
    var count: Int
    var next: String?
    var results: [HubTag]
}

/// A single tag and its per-platform manifests.
struct HubTag: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var tagID: Int?
    var lastUpdated: String?
    var fullSize: Int?
    var images: [HubTagImage]

    var id: String { name }

    /// Real OS/arch platforms, excluding attestation ("unknown") manifests.
    var platforms: [HubTagImage] {
        images.filter { ($0.os ?? "unknown") != "unknown" && $0.architecture != "unknown" }
    }

    /// Compact "linux/arm64, linux/amd64" summary of the real platforms.
    var platformSummary: String {
        platforms.map(\.platformLabel).joined(separator: ", ")
    }

    /// Best size to surface: prefer the host architecture, then the reported
    /// total, then the largest platform manifest.
    var displaySize: Int? {
        let hostArch = ImageReference.hostArchitecture
        if let match = platforms.first(where: { $0.architecture == hostArch }), let size = match.size {
            return size
        }
        return fullSize ?? platforms.compactMap(\.size).max()
    }

    private enum CodingKeys: String, CodingKey {
        case name, images
        case tagID = "id"
        case lastUpdated = "last_updated"
        case fullSize = "full_size"
    }
}

/// One platform manifest listed under a tag.
struct HubTagImage: Codable, Hashable, Sendable {
    var architecture: String
    var variant: String?
    var digest: String?
    var os: String?
    var size: Int?
    var status: String?
    var lastPushed: String?

    /// `linux/arm64/v8`-style label from the OS, architecture, and variant.
    var platformLabel: String {
        var parts = [os ?? "", architecture].filter { !$0.isEmpty }
        if let variant, !variant.isEmpty { parts.append(variant) }
        return parts.joined(separator: "/")
    }

    private enum CodingKeys: String, CodingKey {
        case architecture, variant, digest, os, size, status
        case lastPushed = "last_pushed"
    }
}
