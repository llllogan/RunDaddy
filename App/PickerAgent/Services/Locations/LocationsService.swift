import Foundation

protocol LocationsServicing {
    func getLocation(id: String) async throws -> Location
}

final class LocationsService: LocationsServicing {
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
    
    func getLocation(id: String) async throws -> Location {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }
        
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("locations")
        url.appendPathComponent(id)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocationsServiceError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw LocationsServiceError.locationNotFound
            }
            throw LocationsServiceError.serverError(code: httpResponse.statusCode)
        }
        
        return try decoder.decode(Location.self, from: data)
    }
}

enum LocationsServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case locationNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't connect to RunDaddy right now. Please try again."
        case let .serverError(code):
            return "Fetching location failed with an unexpected error (code \(code))."
        case .locationNotFound:
            return "We couldn't find that location. It may have been removed."
        }
    }
}