import Foundation

protocol SearchServicing {
    func search(query: String) async throws -> SearchResponse
    func fetchSuggestions(lookbackDays: Int?) async throws -> SearchResponse
}

final class SearchService: SearchServicing {
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let credentialStore: CredentialStoring
    
    init(
        urlSession: URLSession = .shared,
        credentialStore: CredentialStoring = CredentialStore()
    ) {
        self.urlSession = urlSession
        self.credentialStore = credentialStore
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }
    
    func search(query: String) async throws -> SearchResponse {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SearchServiceError.emptyQuery
        }
        
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }
        
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("analytics")
        url.appendPathComponent("search")
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        let resolvedURL = components?.url ?? url
        
        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchServiceError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            throw SearchServiceError.serverError(code: httpResponse.statusCode)
        }
        
        return try decoder.decode(SearchResponse.self, from: data)
    }
    
    func fetchSuggestions(lookbackDays: Int? = nil) async throws -> SearchResponse {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }
        
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("analytics")
        url.appendPathComponent("search")
        url.appendPathComponent("suggestions")
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let lookbackDays {
            components?.queryItems = [URLQueryItem(name: "lookbackDays", value: String(lookbackDays))]
        }
        let resolvedURL = components?.url ?? url
        
        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchServiceError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            throw SearchServiceError.serverError(code: httpResponse.statusCode)
        }
        
        return try decoder.decode(SearchResponse.self, from: data)
    }
}

enum SearchServiceError: LocalizedError {
    case emptyQuery
    case invalidResponse
    case serverError(code: Int)
    
    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Search query cannot be empty"
        case .invalidResponse:
            return "We couldn't connect to RunDaddy right now. Please try again."
        case let .serverError(code):
            return "Search failed with an unexpected error (code \(code))."
        }
    }
}
