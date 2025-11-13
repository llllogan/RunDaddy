import Foundation

protocol SkusServicing {
    func getSku(id: String) async throws -> SKU
    func getSkuStats(id: String, period: SkuPeriod) async throws -> SkuStatsResponse
    func updateCheeseStatus(id: String, isCheeseAndCrackers: Bool) async throws
}

final class SkusService: SkusServicing {
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
    
    func getSku(id: String) async throws -> SKU {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }
        
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("skus")
        url.appendPathComponent(id)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkusServiceError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw SkusServiceError.skuNotFound
            }
            throw SkusServiceError.serverError(code: httpResponse.statusCode)
        }
        
        return try decoder.decode(SKU.self, from: data)
    }
    
    func getSkuStats(id: String, period: SkuPeriod) async throws -> SkuStatsResponse {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }
        
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("skus")
        url.appendPathComponent(id)
        url.appendPathComponent("stats")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "period", value: period.rawValue)]
        let resolvedURL = components?.url ?? url
        
        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkusServiceError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw SkusServiceError.skuNotFound
            }
            throw SkusServiceError.serverError(code: httpResponse.statusCode)
        }
        
        return try decoder.decode(SkuStatsResponse.self, from: data)
    }
    
    func updateCheeseStatus(id: String, isCheeseAndCrackers: Bool) async throws {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }
        
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("skus")
        url.appendPathComponent(id)
        url.appendPathComponent("cheese-and-crackers")
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["isCheeseAndCrackers": isCheeseAndCrackers]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkusServiceError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw SkusServiceError.insufficientPermissions
            }
            if httpResponse.statusCode == 404 {
                throw SkusServiceError.skuNotFound
            }
            throw SkusServiceError.serverError(code: httpResponse.statusCode)
        }
    }
}

enum SkusServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case skuNotFound
    case insufficientPermissions
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't connect to RunDaddy right now. Please try again."
        case let .serverError(code):
            return "SKU operation failed with an unexpected error (code \(code))."
        case .skuNotFound:
            return "We couldn't find that SKU. It may have been removed."
        case .insufficientPermissions:
            return "You don't have permission to update this SKU."
        }
    }
}
