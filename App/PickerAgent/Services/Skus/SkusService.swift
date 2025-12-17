import Foundation

protocol SkusServicing {
    func getSku(id: String) async throws -> SKU
    func getColdChestSkus() async throws -> [SKU]
    func getColdChestSkuCount() async throws -> Int
    func getSkusMissingWeightCount() async throws -> Int
    func bulkUpdateWeight(skuIds: [String], weight: Double) async throws -> Int
    func bulkAddToColdChest(skuIds: [String]) async throws -> Int
    func getSkuStats(
        id: String,
        period: SkuPeriod,
        locationId: String?,
        machineId: String?
    ) async throws -> SkuStatsResponse
    func updateColdChestStatus(id: String, isFreshOrFrozen: Bool) async throws
    func updateWeight(id: String, weight: Double?) async throws
    func updateLabelColour(id: String, labelColourHex: String?) async throws
    func updateExpiryDays(id: String, expiryDays: Int) async throws
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

    func getColdChestSkus() async throws -> [SKU] {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }

        var url = AppConfig.apiBaseURL
        url.appendPathComponent("skus")
        url.appendPathComponent("cold-chest")

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
            throw SkusServiceError.serverError(code: httpResponse.statusCode)
        }

        return try decoder.decode([SKU].self, from: data)
    }

    func getColdChestSkuCount() async throws -> Int {
        try await getSkuCount(pathComponents: ["skus", "cold-chest", "count"])
    }

    func getSkusMissingWeightCount() async throws -> Int {
        try await getSkuCount(pathComponents: ["skus", "missing-weight", "count"])
    }

    func bulkUpdateWeight(skuIds: [String], weight: Double) async throws -> Int {
        try await bulkUpdate(
            pathComponents: ["skus", "bulk", "weight"],
            body: ["skuIds": skuIds, "weight": weight]
        )
    }

    func bulkAddToColdChest(skuIds: [String]) async throws -> Int {
        try await bulkUpdate(
            pathComponents: ["skus", "bulk", "cold-chest"],
            body: ["skuIds": skuIds]
        )
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

    func updateExpiryDays(id: String, expiryDays: Int) async throws {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }

        var url = AppConfig.apiBaseURL
        url.appendPathComponent("skus")
        url.appendPathComponent(id)
        url.appendPathComponent("expiry-days")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "expiryDays": expiryDays
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

    private func getSkuCount(pathComponents: [String]) async throws -> Int {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }

        var url = AppConfig.apiBaseURL
        pathComponents.forEach { url.appendPathComponent($0) }

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
            throw SkusServiceError.serverError(code: httpResponse.statusCode)
        }

        return try decoder.decode(SkuCountResponse.self, from: data).count
    }

    private func bulkUpdate(pathComponents: [String], body: [String: Any]) async throws -> Int {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }

        var url = AppConfig.apiBaseURL
        pathComponents.forEach { url.appendPathComponent($0) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

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
            throw SkusServiceError.serverError(code: httpResponse.statusCode)
        }

        return try decoder.decode(BulkUpdateResponse.self, from: data).updatedCount
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

private struct SkuCountResponse: Decodable {
    let count: Int
}

private struct BulkUpdateResponse: Decodable {
    let updatedCount: Int
}
