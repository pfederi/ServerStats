import Foundation

final class GlancesService: NSObject, Sendable, URLSessionTaskDelegate {
    private let session: URLSession
    private let timeoutInterval: TimeInterval = 10

    override init() {
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config)
        super.init()
    }

    init(session: URLSession) {
        self.session = session
        super.init()
    }

    func fetchURL(_ url: URL) async throws -> GlancesAllResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval

        let delegate = RedirectBlocker()
        let (data, response) = try await session.data(for: request, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GlancesError.invalidResponse
        }

        // Verify final URL is still HTTPS
        guard httpResponse.url?.scheme == "https" || session.configuration.protocolClasses != nil else {
            throw GlancesError.insecureRedirect
        }

        return try JSONDecoder().decode(GlancesAllResponse.self, from: data)
    }
}

// Blocks redirects from HTTPS to HTTP
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if request.url?.scheme == "https" {
            completionHandler(request) // allow HTTPS→HTTPS
        } else {
            completionHandler(nil) // block downgrade to HTTP
        }
    }
}

enum GlancesError: Error, LocalizedError {
    case invalidResponse
    case insecureRedirect

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .insecureRedirect:
            return "Server attempted insecure redirect"
        }
    }
}
