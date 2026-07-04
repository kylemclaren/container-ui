import Foundation

/// Abstraction over HTTP GETs so registry/network services can be unit-tested
/// against recorded fixtures without a live connection — the network-side
/// counterpart to `CommandRunner`.
protocol HTTPClient: Sendable {
    /// Performs a GET and returns the raw body plus the HTTP response.
    /// Throws `CancellationError` if the task was cancelled, otherwise `HubError`.
    func get(_ url: URL) async throws -> (Data, HTTPURLResponse)
}

/// Typed failures from a Docker Hub request.
enum HubError: Error, Sendable, Equatable {
    /// The request never reached Docker Hub (no network, DNS, timeout…).
    case offline
    /// Docker Hub replied with a non-2xx status.
    case http(status: Int)
    /// The body didn't decode into the expected shape.
    case decodingFailed(message: String)
    /// The response wasn't an HTTP response at all.
    case invalidResponse
}

extension HubError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .offline:
            return "Couldn’t reach Docker Hub. Check your internet connection and try again."
        case .http(let status):
            return "Docker Hub returned an error (HTTP \(status))."
        case .decodingFailed:
            return "Docker Hub sent a response ContainerUI couldn’t read."
        case .invalidResponse:
            return "Docker Hub returned an unexpected response."
        }
    }
}

/// `HTTPClient` backed by `URLSession`, tuned for a responsive search box:
/// short timeout, fail-fast (no waiting for connectivity), and a descriptive
/// `User-Agent`.
struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.waitsForConnectivity = false
            config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
            self.session = URLSession(configuration: config)
        }
    }

    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HubError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw HubError.invalidResponse }
        return (data, http)
    }

    private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "ContainerUI/\(version)"
    }()
}
