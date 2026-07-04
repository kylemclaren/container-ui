import Foundation
import Testing

/// Verifies Docker Hub URL building, response decoding, service error mapping, and
/// the formatting helpers the Docker Hub UI relies on.
@Suite("Docker Hub")
struct DockerHubTests {
    // MARK: URL building

    @Test func searchURLBuilding() throws {
        let url = DockerHubService.searchURL(query: "my app", page: 2, pageSize: 10)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "hub.docker.com")
        #expect(components.path == "/v2/search/repositories/")

        let query = try #require(components.percentEncodedQuery)
        #expect(query.contains("query=my%20app") || query.contains("query=my+app"))
        #expect(query.contains("page=2"))
        #expect(query.contains("page_size=10"))
    }

    @Test func tagsURLBuilding() throws {
        let url = DockerHubService.tagsURL(namespace: "library", repository: "nginx")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/v2/repositories/library/nginx/tags/")

        let query = try #require(components.percentEncodedQuery)
        #expect(query.contains("ordering=last_updated"))
    }

    // MARK: Search decoding

    @Test("Search response decodes repos, namespace/repository split, and pull references")
    func searchDecoding() throws {
        let response = try DockerHubService.decoder.decode(HubSearchResponse.self, from: Fixtures.data(Fixtures.hubSearch))
        #expect(response.results.count == 3)

        let nginx = try #require(response.results.first { $0.repoName == "nginx" })
        #expect(nginx.isOfficial)
        #expect(nginx.starCount == 21318)
        #expect(nginx.pullCount == 13_114_222_271)
        #expect(nginx.namespace == "library")
        #expect(nginx.repository == "nginx")
        #expect(nginx.pullReference() == "docker.io/library/nginx:latest")

        let grafana = try #require(response.results.first { $0.repoName == "grafana/grafana" })
        #expect(grafana.namespace == "grafana")
        #expect(grafana.repository == "grafana")
        #expect(!grafana.isOfficial)
        #expect(grafana.pullReference(tag: "10.0") == "docker.io/grafana/grafana:10.0")

        let cimg = try #require(response.results.first { $0.repoName == "cimg/postgres" })
        #expect(cimg.shortDescription == "")
    }

    // MARK: Tags decoding

    @Test("Tags response decodes platforms, excluding unknown attestation manifests")
    func tagsDecoding() throws {
        let response = try DockerHubService.decoder.decode(HubTagsResponse.self, from: Fixtures.data(Fixtures.hubTags))
        #expect(response.results.count == 2)

        let latest = try #require(response.results.first { $0.name == "latest" })
        #expect(latest.images.count == 3)          // raw manifests, including the "unknown" one
        #expect(latest.platforms.count == 2)        // "unknown" excluded
        #expect(latest.platformSummary.contains("linux/amd64"))
        #expect(latest.platformSummary.contains("linux/arm64/v8"))
        #expect(!latest.platformSummary.contains("unknown"))
        #expect(latest.displaySize != nil)
        #expect(latest.lastUpdated == "2026-06-24T04:51:06.973034832Z")   // survives as String
    }

    // MARK: Service error mapping

    @Test func searchMapsHTTPErrorStatus() async throws {
        let service = DockerHubService(client: MockHTTPClient(status: 503, body: "nope"))

        do {
            _ = try await service.search(query: "x")
            Issue.record("expected search() to throw")
        } catch let error as HubError {
            #expect(error == .http(status: 503))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func searchMapsDecodingFailure() async throws {
        let service = DockerHubService(client: MockHTTPClient(status: 200, body: "{ not json"))

        do {
            _ = try await service.search(query: "x")
            Issue.record("expected search() to throw")
        } catch let error as HubError {
            guard case .decodingFailed = error else {
                Issue.record("expected .decodingFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func searchSucceedsAndRecordsRequestedURL() async throws {
        let mock = MockHTTPClient(status: 200, body: Fixtures.hubSearch)
        let service = DockerHubService(client: mock)

        let results = try await service.search(query: "nginx")

        #expect(results.count == 3)
        #expect(mock.lastURL?.host == "hub.docker.com")
    }

    // MARK: Formatting.compactCount

    @Test func compactCount() {
        #expect(Formatting.compactCount(999) == "999")
        #expect(Formatting.compactCount(1_000) == "1K")
        #expect(Formatting.compactCount(1_500) == "1.5K")
        #expect(Formatting.compactCount(21_318) == "21.3K")
        #expect(Formatting.compactCount(1_200_000) == "1.2M")
        #expect(Formatting.compactCount(13_114_222_271) == "13.1B")
        // Unit-boundary rounding: a value that rounds up to 1000 within a band
        // must promote to the next unit, not render "1000M"/"1000K".
        #expect(Formatting.compactCount(999_949) == "999.9K")
        #expect(Formatting.compactCount(999_950) == "1M")
        #expect(Formatting.compactCount(999_999) == "1M")
        #expect(Formatting.compactCount(999_949_999) == "999.9M")
        #expect(Formatting.compactCount(999_950_000) == "1B")
        #expect(Formatting.compactCount(999_999_999) == "1B")
    }

    // MARK: Formatting.relativeISO8601

    @Test func relativeISO8601() {
        #expect(Formatting.relativeISO8601("2026-06-24T04:51:06.973034832Z") != nil)   // fractional seconds
        #expect(Formatting.relativeISO8601("2026-06-24T04:51:00Z") != nil)             // plain
        #expect(Formatting.relativeISO8601("not a date") == nil)
        #expect(Formatting.relativeISO8601(nil) == nil)
    }
}
