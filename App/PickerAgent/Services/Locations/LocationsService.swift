import Foundation

protocol LocationsServicing {
    func getLocation(id: String) async throws -> Location
    func getLocationStats(id: String, period: SkuPeriod) async throws -> LocationStatsResponse
    func updateLocation(
        id: String,
        openingTimeMinutes: Int?,
        closingTimeMinutes: Int?,
        dwellTimeMinutes: Int?
    ) async throws -> Location
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

    func updateLocation(
        id: String,
        openingTimeMinutes: Int?,
        closingTimeMinutes: Int?,
        dwellTimeMinutes: Int?
    ) async throws -> Location {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }

        var url = AppConfig.apiBaseURL
        url.appendPathComponent("locations")
        url.appendPathComponent(id)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = UpdateLocationRequest(
            openingTimeMinutes: openingTimeMinutes,
            closingTimeMinutes: closingTimeMinutes,
            dwellTimeMinutes: dwellTimeMinutes
        )
        request.httpBody = try JSONEncoder().encode(payload)

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
            if httpResponse.statusCode == 400 {
                let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                if let message = error?.error?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !message.isEmpty {
                    throw LocationsServiceError.validationFailed(message: message)
                }
                throw LocationsServiceError.validationFailed(message: "We couldn't update this location.")
            }
            throw LocationsServiceError.serverError(code: httpResponse.statusCode)
        }

        return try decoder.decode(Location.self, from: data)
    }

    func getLocationStats(id: String, period: SkuPeriod) async throws -> LocationStatsResponse {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }

        var url = AppConfig.apiBaseURL
        url.appendPathComponent("locations")
        url.appendPathComponent(id)
        url.appendPathComponent("stats")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "period", value: period.rawValue)
        ]
        let resolvedURL = components?.url ?? url

        var request = URLRequest(url: resolvedURL)
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

        return try decoder.decode(LocationStatsResponse.self, from: data)
    }
}

private struct UpdateLocationRequest: Encodable {
    let openingTimeMinutes: Int?
    let closingTimeMinutes: Int?
    let dwellTimeMinutes: Int?
}

private struct ErrorResponse: Decodable {
    let error: String?
}

enum LocationsServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case locationNotFound
    case validationFailed(message: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't connect to RunDaddy right now. Please try again."
        case let .serverError(code):
            return "Location request failed with an unexpected error (code \(code))."
        case .locationNotFound:
            return "We couldn't find that location. It may have been removed."
        case let .validationFailed(message):
            return message
        }
    }
}
