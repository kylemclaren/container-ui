import Foundation

/// Pure formatting helpers shared across the UI. Kept dependency-free and
/// deterministic (relative-date helpers take an explicit `now`) so they're
/// straightforward to unit-test.
enum Formatting {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    /// Human-readable byte count, e.g. `1.1 GB`.
    static func bytes(_ value: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(clamping: value))
    }

    static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: max(0, value))
    }

    /// Strips an algorithm prefix (`sha256:`) and truncates to `length` hex chars.
    static func shortDigest(_ digest: String, length: Int = 12) -> String {
        let hex = digest.split(separator: ":").last.map(String.init) ?? digest
        return String(hex.prefix(length))
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Relative time such as `3 min ago`, computed against `now`.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    /// Memory as `used / limit`, e.g. `512 MB / 1 GB`.
    static func memory(used: UInt64?, limit: UInt64?) -> String {
        switch (used, limit) {
        case let (.some(u), .some(l)): return "\(bytes(u)) / \(bytes(l))"
        case let (.some(u), .none): return bytes(u)
        default: return "—"
        }
    }

    /// CPU count label, e.g. `4 CPUs` / `1 CPU`.
    static func cpus(_ count: Int) -> String {
        "\(count) CPU\(count == 1 ? "" : "s")"
    }
}
