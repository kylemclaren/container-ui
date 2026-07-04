import Foundation

/// Read-only access to Docker Hub's public API for image discovery.
///
/// This is the one service that reaches the network directly instead of shelling
/// out to `container`, because the CLI has no registry-search command. It's
/// backed by an injectable `HTTPClient` so it can be unit-tested against recorded
/// fixtures, mirroring how the CLI services use `CommandRunner`.
struct DockerHubService: Sendable {
    let client: HTTPClient

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    /// Docker Hub keys are mapped with explicit `CodingKeys` per model, so no key
    /// strategy — matching the CLI decoder's house rule.
    static let decoder = JSONDecoder()

    private static let host = "hub.docker.com"

    // MARK: URL builders (pure, unit-tested)

    static func searchURL(query: String, page: Int = 1, pageSize: Int = 25) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v2/search/repositories/"
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ]
        return components.url!
    }

    static func tagsURL(namespace: String, repository: String, pageSize: Int = 50) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v2/repositories/\(namespace)/\(repository)/tags/"
        components.queryItems = [
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "ordering", value: "last_updated"),
        ]
        return components.url!
    }

    // MARK: Operations

    /// Searches Docker Hub repositories, newest/most-relevant first (Hub's order).
    func search(query: String, page: Int = 1, pageSize: Int = 25) async throws -> [HubRepository] {
        let url = Self.searchURL(query: query, page: page, pageSize: pageSize)
        return try await fetch(HubSearchResponse.self, from: url).results
    }

    /// Lists a repository's tags, most-recently-updated first.
    func tags(namespace: String, repository: String, pageSize: Int = 50) async throws -> [HubTag] {
        let url = Self.tagsURL(namespace: namespace, repository: repository, pageSize: pageSize)
        return try await fetch(HubTagsResponse.self, from: url).results
    }

    // MARK: Fetch + decode

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await client.get(url)
        guard (200..<300).contains(response.statusCode) else {
            throw HubError.http(status: response.statusCode)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw HubError.decodingFailed(message: String(describing: error))
        }
    }
}
