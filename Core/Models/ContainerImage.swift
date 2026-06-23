import Foundation

/// A local image as returned by `container image list --format json` and
/// `container image inspect` (the CLI's `ImageResource`). The wire object's
/// top-level `id` is the content digest's hex (without the `sha256:` prefix);
/// the UI's `Identifiable` id is the unique reference name instead, since two
/// tags of the same content are distinct list rows.
struct ContainerImage: Codable, Hashable, Identifiable, Sendable {
    var contentID: String
    var configuration: ImageConfiguration
    var variants: [ImageVariant]

    var id: String { configuration.name }

    private enum CodingKeys: String, CodingKey {
        case contentID = "id"
        case configuration
        case variants
    }
}

extension ContainerImage {
    var reference: String { configuration.name }
    var createdAt: Date { configuration.creationDate }

    /// Short content id (12 hex chars), like other container tools display.
    var shortID: String { String(contentID.prefix(12)) }

    /// Parsed reference (registry / repository / tag).
    var parsedReference: ImageReference { ImageReference.parse(configuration.name) }

    /// The platform variant to summarize in lists: prefer the host architecture,
    /// then linux, then the largest.
    var primaryVariant: ImageVariant? {
        let hostArch = ImageReference.hostArchitecture
        return variants.first(where: { $0.platform.architecture == hostArch && $0.platform.os == "linux" })
            ?? variants.first(where: { $0.platform.os == "linux" })
            ?? variants.max(by: { $0.size < $1.size })
    }

    /// Display size: the primary variant's total size (or the max across variants).
    var displaySize: Int64 {
        primaryVariant?.size ?? variants.map(\.size).max() ?? 0
    }

    /// Distinct OS/arch platforms present (excluding attestation "unknown").
    var platforms: [OCIPlatform] {
        variants.map(\.platform).filter { $0.os != "unknown" && $0.architecture != "unknown" }
    }

    /// Labels carried on the index descriptor, if any.
    var labels: [String: String] { configuration.descriptor.annotations ?? [:] }
}

struct ImageConfiguration: Codable, Hashable, Sendable {
    /// Full normalized reference, e.g. `docker.io/library/alpine:latest`.
    var name: String
    /// `Date` encoded as ISO-8601 *without* fractional seconds.
    var creationDate: Date
    /// The image index descriptor.
    var descriptor: OCIDescriptor
}

/// One platform manifest of an image.
struct ImageVariant: Codable, Hashable, Sendable, Identifiable {
    var platform: OCIPlatform
    var digest: String
    /// Total bytes = index descriptor + config blob + sum(layers).
    var size: Int64
    var config: OCIImage

    var id: String { digest }
}

/// The OCI image config (`config.v1+json`) for a variant. `created`/`history`
/// timestamps are verbatim RFC3339 strings (often with nanoseconds), so they're
/// decoded as `String`, not `Date`.
struct OCIImage: Codable, Hashable, Sendable {
    var created: String?
    var author: String?
    var architecture: String
    var os: String
    var variant: String?
    var config: OCIImageConfig?
    var rootfs: Rootfs
    var history: [History]?

    private enum CodingKeys: String, CodingKey {
        case created, author, architecture, os, variant, config, rootfs, history
        case osVersion, osFeatures
    }
}

/// The runnable config block. Note the OCI spec's **PascalCase** keys.
struct OCIImageConfig: Codable, Hashable, Sendable {
    var user: String?
    var env: [String]?
    var entrypoint: [String]?
    var cmd: [String]?
    var workingDir: String?
    var labels: [String: String]?
    var stopSignal: String?

    private enum CodingKeys: String, CodingKey {
        case user = "User"
        case env = "Env"
        case entrypoint = "Entrypoint"
        case cmd = "Cmd"
        case workingDir = "WorkingDir"
        case labels = "Labels"
        case stopSignal = "StopSignal"
    }
}

/// The layer filesystem set. `diff_ids` is snake_case on the wire.
struct Rootfs: Codable, Hashable, Sendable {
    var type: String
    var diffIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case type
        case diffIDs = "diff_ids"
    }
}

/// One image build-history entry. `created_by`/`empty_layer` are snake_case.
struct History: Codable, Hashable, Sendable {
    var created: String?
    var createdBy: String?
    var author: String?
    var comment: String?
    var emptyLayer: Bool?

    private enum CodingKeys: String, CodingKey {
        case created
        case createdBy = "created_by"
        case author
        case comment
        case emptyLayer = "empty_layer"
    }
}
