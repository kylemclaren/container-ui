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

    /// Compact human count for large tallies (stars, pulls): `999`, `21.3K`,
    /// `1.2M`, `13.1B`. Trailing `.0` is dropped (`1.0K` → `1K`).
    static func compactCount(_ value: Int) -> String {
        // Thresholds sit just under each unit so a value that rounds up to
        // "1000" within a band (e.g. 999_999_999) promotes to the next unit
        // ("1B") rather than rendering "1000M".
        let magnitude = abs(value)
        switch magnitude {
        case 999_950_000...:
            return scaled(Double(value) / 1_000_000_000) + "B"
        case 999_950...:
            return scaled(Double(value) / 1_000_000) + "M"
        case 1_000...:
            return scaled(Double(value) / 1_000) + "K"
        default:
            return String(value)
        }
    }

    private static func scaled(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Relative time from an ISO-8601 string that may or may not carry fractional
    /// seconds (Docker Hub uses nanoseconds). Returns nil if it can't be parsed.
    static func relativeISO8601(_ string: String?, now: Date = Date()) -> String? {
        guard let string, !string.isEmpty else { return nil }
        guard let date = iso8601Fractional.date(from: string) ?? iso8601Plain.date(from: string) else {
            return nil
        }
        return relative(date, now: now)
    }
}
