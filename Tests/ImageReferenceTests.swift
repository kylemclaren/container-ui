import Foundation
import Testing

@Suite("Image reference parsing")
struct ImageReferenceTests {
    @Test func fullyQualified() {
        let ref = ImageReference.parse("docker.io/library/alpine:latest")
        #expect(ref.registry == "docker.io")
        #expect(ref.repository == "library/alpine")
        #expect(ref.tag == "latest")
        #expect(ref.name == "alpine")
        #expect(ref.displayName == "alpine:latest")
    }

    @Test func bareName() {
        let ref = ImageReference.parse("nginx")
        #expect(ref.registry == nil)
        #expect(ref.repository == "nginx")
        #expect(ref.tag == nil)
        #expect(ref.displayName == "nginx")
    }

    @Test func localRegistryWithPort() {
        let ref = ImageReference.parse("localhost:5000/app:1.0")
        #expect(ref.registry == "localhost:5000")
        #expect(ref.repository == "app")
        #expect(ref.tag == "1.0")
    }

    @Test func digestReference() {
        let ref = ImageReference.parse("ubuntu@sha256:abc123")
        #expect(ref.repository == "ubuntu")
        #expect(ref.digest == "sha256:abc123")
        #expect(ref.tag == nil)
    }

    @Test func ghcrNoTag() {
        let ref = ImageReference.parse("ghcr.io/owner/repo")
        #expect(ref.registry == "ghcr.io")
        #expect(ref.repository == "owner/repo")
        #expect(ref.tag == nil)
        #expect(ref.name == "repo")
    }
}
