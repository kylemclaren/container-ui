import Foundation

/// An `HTTPClient` test double: returns programmed responses and records the URLs
/// it was asked to fetch, so `DockerHubService` can be tested without a network.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _requestedURLs: [URL] = []

    var responder: @Sendable (URL) throws -> (Data, HTTPURLResponse)

    init(responder: @escaping @Sendable (URL) throws -> (Data, HTTPURLResponse)) {
        self.responder = responder
    }

    /// Convenience: always reply with `body` at the given HTTP status.
    convenience init(status: Int = 200, body: String) {
        self.init(responder: { url in
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(body.utf8), response)
        })
    }

    var requestedURLs: [URL] { lock.lock(); defer { lock.unlock() }; return _requestedURLs }
    var lastURL: URL? { lock.lock(); defer { lock.unlock() }; return _requestedURLs.last }

    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); _requestedURLs.append(url); lock.unlock()
        return try responder(url)
    }
}
