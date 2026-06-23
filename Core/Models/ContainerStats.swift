import Foundation

/// A single resource-usage sample from
/// `container stats --no-stream --format json`. Every numeric field is optional
/// (omitted when the backend can't sample it). The CLI computes a CPU % for its
/// table from two samples; JSON only carries the raw cumulative counter.
struct ContainerStats: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var memoryUsageBytes: UInt64?
    var memoryLimitBytes: UInt64?
    var cpuUsageUsec: UInt64?
    var networkRxBytes: UInt64?
    var networkTxBytes: UInt64?
    var blockReadBytes: UInt64?
    var blockWriteBytes: UInt64?
    var numProcesses: UInt64?
}

extension ContainerStats {
    /// Memory usage as a fraction of the limit (0...1), if both are known.
    var memoryFraction: Double? {
        guard let usage = memoryUsageBytes, let limit = memoryLimitBytes, limit > 0 else { return nil }
        return min(1.0, Double(usage) / Double(limit))
    }
}
