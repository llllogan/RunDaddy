import Foundation

protocol SkusServicing {
    func getSku(id: String) async throws -> SKU
    func getSkuStats(
        id: String,
        period: SkuPeriod,
        locationId: String?,
        machineId: String?
    ) async throws -> SkuStatsResponse
    func updateColdChestStatus(id: String, isFreshOrFrozen: Bool) async throws
    func updateWeight(id: String, weight: Double?) async throws
    func updateLabelColour(id: String, labelColourHex: String?) async throws
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
    
    func getSkuStats(
        id: String,
        period: SkuPeriod,
        locationId: String? = nil,
        machineId: String? = nil
    ) async throws -> SkuStatsResponse {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }
        
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("skus")
        url.appendPathComponent(id)
        url.appendPathComponent("stats")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "period", value: period.rawValue)
        ]
        if let locationId, !locationId.isEmpty {
            queryItems.append(URLQueryItem(name: "locationId", value: locationId))
        }
        if let machineId, !machineId.isEmpty {
            queryItems.append(URLQueryItem(name: "machineId", value: machineId))
        }
        components?.queryItems = queryItems
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
    
    func updateColdChestStatus(id: String, isFreshOrFrozen: Bool) async throws {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }
        
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("skus")
        url.appendPathComponent(id)
        url.appendPathComponent("fresh-or-frozen")
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["isFreshOrFrozen": isFreshOrFrozen]
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

    func updateWeight(id: String, weight: Double?) async throws {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }

        var url = AppConfig.apiBaseURL
        url.appendPathComponent("skus")
        url.appendPathComponent(id)
        url.appendPathComponent("weight")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "weight": weight as Any? ?? NSNull()
        ]
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

    func updateLabelColour(id: String, labelColourHex: String?) async throws {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }

        var url = AppConfig.apiBaseURL
        url.appendPathComponent("skus")
        url.appendPathComponent(id)
        url.appendPathComponent("label-colour")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "labelColour": labelColourHex as Any? ?? NSNull()
        ]
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
