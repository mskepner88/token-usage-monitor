import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPClient: Sendable {
    public init() {}

    public func getJSON(
        url: URL,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        return try await send(request)
    }

    public func postJSON(
        url: URL,
        body: [String: Any],
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        return (data, http)
    }
}

public enum ProviderError: LocalizedError, Sendable {
    case invalidResponse
    case http(Int, String)
    case missingCredentials(String)
    case decoding(String)
    case notConfigured(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid HTTP response"
        case .http(let code, let body):
            "HTTP \(code): \(body)"
        case .missingCredentials(let detail):
            detail
        case .decoding(let detail):
            "Could not parse response: \(detail)"
        case .notConfigured(let detail):
            detail
        }
    }
}
