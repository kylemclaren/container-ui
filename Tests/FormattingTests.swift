import Foundation
import Testing

@Suite("Formatting")
struct FormattingTests {
    @Test func shortDigestStripsAlgorithmPrefix() {
        #expect(Formatting.shortDigest("sha256:abcdef0123456789", length: 12) == "abcdef012345")
        #expect(Formatting.shortDigest("deadbeefcafe", length: 4) == "dead")
        #expect(Formatting.shortDigest("sha256:abc", length: 12) == "abc")
    }

    @Test func cpuPluralization() {
        #expect(Formatting.cpus(1) == "1 CPU")
        #expect(Formatting.cpus(4) == "4 CPUs")
        #expect(Formatting.cpus(0) == "0 CPUs")
    }

    @Test func memoryFormatting() {
        #expect(Formatting.memory(used: nil, limit: nil) == "—")
        #expect(Formatting.memory(used: 1_048_576, limit: nil).contains("MB"))
        #expect(Formatting.memory(used: 1_048_576, limit: 2_097_152).contains("/"))
    }

    @Test func byteUnits() {
        #expect(Formatting.bytes(UInt64(1_048_576)).contains("MB"))
        #expect(Formatting.bytes(UInt64(2_000_000_000)).contains("GB"))
    }
}
