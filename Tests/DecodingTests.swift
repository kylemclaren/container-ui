import Foundation
import Testing

/// Verifies our Codable models decode the exact JSON the `container` CLI emits.
@Suite("Decoding")
struct DecodingTests {
    private let decoder = ContainerCLI.decoder

    @Test("Container list decodes both running and stopped entries")
    func containerList() throws {
        let containers = try decoder.decode([Container].self, from: Fixtures.data(Fixtures.containerList))
        #expect(containers.count == 2)

        let web = try #require(containers.first { $0.id == "web" })
        #expect(web.isRunning)
        #expect(web.state == .running)
        #expect(web.imageReference == "docker.io/library/nginx:latest")
        #expect(web.cpus == 4)
        #expect(web.memoryInBytes == 1_073_741_824)
        #expect(web.primaryIPv4 == "192.168.64.3/24")
        #expect(web.primaryIPv4Address == "192.168.64.3")
        #expect(web.startedAt != nil)
        #expect(web.configuration.publishedPorts.first?.hostPort == 8080)
        #expect(web.configuration.labels["com.example.role"] == "web")
        #expect(web.configuration.mounts.first?.destination == "/data")
        #expect(web.configuration.initProcess.user.display == "0:0")

        let db = try #require(containers.first { $0.id == "db" })
        #expect(db.state == .stopped)
        #expect(db.startedAt == nil)        // startedDate omitted for stopped containers
        #expect(db.primaryIPv4 == nil)      // empty status.networks
    }

    @Test("Unknown run states decode as .unknown")
    func unknownState() throws {
        let json = #"{"state":"frobnicating","networks":[]}"#
        let status = try decoder.decode(ContainerStatus.self, from: Fixtures.data(json))
        #expect(status.state == .unknown)
    }

    @Test("Stats decode with optional numeric fields")
    func stats() throws {
        let stats = try decoder.decode([ContainerStats].self, from: Fixtures.data(Fixtures.stats))
        let sample = try #require(stats.first)
        #expect(sample.id == "web")
        #expect(sample.memoryUsageBytes == 52_428_800)
        #expect(sample.numProcesses == 12)
        let fraction = try #require(sample.memoryFraction)
        #expect(abs(fraction - 0.048828125) < 0.0001)
    }

    @Test("Image list decodes, including PascalCase config and snake_case rootfs")
    func imageList() throws {
        let images = try decoder.decode([ContainerImage].self, from: Fixtures.data(Fixtures.imageList))
        let image = try #require(images.first)
        #expect(image.reference == "docker.io/library/alpine:latest")
        #expect(image.shortID == "1a2b3c4d5e6f")
        #expect(image.displaySize == 3_987_654)
        #expect(image.labels["org.opencontainers.image.ref.name"] == "alpine:latest")

        let variant = try #require(image.primaryVariant)
        #expect(variant.platform.architecture == "arm64")
        #expect(variant.platform.display == "linux/arm64/v8")
        #expect(variant.config.config?.cmd == ["/bin/sh"])               // PascalCase "Cmd"
        #expect(variant.config.config?.env == ["PATH=/usr/local/sbin:/usr/local/bin"])
        #expect(variant.config.rootfs.diffIDs.count == 2)                // snake_case "diff_ids"
    }

    @Test("System status decodes when running")
    func systemStatusRunning() throws {
        let status = try decoder.decode(SystemStatus.self, from: Fixtures.data(Fixtures.systemStatusRunning))
        #expect(status.isRunning)
        #expect(status.state == .running)
        #expect(status.apiServerVersion == "0.4.1")
        #expect(status.logRoot != nil)
    }

    @Test("System status decodes when unregistered (logRoot omitted)")
    func systemStatusDown() throws {
        let status = try decoder.decode(SystemStatus.self, from: Fixtures.data(Fixtures.systemStatusUnregistered))
        #expect(!status.isRunning)
        #expect(status.state == .unregistered)
        #expect(status.logRoot == nil)
    }

    @Test("Disk usage decodes UInt64 sizes")
    func diskUsage() throws {
        let usage = try decoder.decode(DiskUsageStats.self, from: Fixtures.data(Fixtures.diskUsage))
        #expect(usage.images.total == 5)
        #expect(usage.images.sizeInBytes == 1_073_741_824)
        #expect(usage.images.reclaimable == 524_288_000)
        #expect(usage.containers.active == 1)
    }

    @Test("Version array has 2 elements up, 1 down")
    func version() throws {
        let up = try decoder.decode([VersionInfo].self, from: Fixtures.data(Fixtures.versionUp))
        #expect(up.count == 2)
        #expect(up.first?.appName == "container")
        #expect(up.last?.appName == "container-apiserver")

        let down = try decoder.decode([VersionInfo].self, from: Fixtures.data(Fixtures.versionDown))
        #expect(down.count == 1)
    }
}
