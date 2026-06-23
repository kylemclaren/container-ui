import Foundation

/// OCI content descriptor as emitted by the CLI (camelCase keys).
struct OCIDescriptor: Codable, Hashable, Sendable {
    var mediaType: String
    var digest: String
    var size: Int64
    var annotations: [String: String]?
    var platform: OCIPlatform?
    var urls: [String]?
    var artifactType: String?
}

/// OCI platform. The CLI's custom encoder emits only `os`, `architecture`, and
/// (when present) `variant`; `osVersion`/`osFeatures` are never serialized.
struct OCIPlatform: Codable, Hashable, Sendable {
    var os: String
    var architecture: String
    var variant: String?

    /// e.g. `linux/arm64/v8` or `linux/amd64`.
    var display: String {
        var value = "\(os)/\(architecture)"
        if let variant, !variant.isEmpty { value += "/\(variant)" }
        return value
    }
}
