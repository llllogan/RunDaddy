import Foundation

struct CompanyFeatures: Equatable, Decodable {
    struct Tier: Equatable, Decodable {
        let id: String
        let name: String
        let maxOwners: Int
        let maxAdmins: Int
        let maxPickers: Int
        let canBreakDownRun: Bool
    }

    struct FeatureFlags: Equatable, Decodable {
        let canBreakDownRun: Bool
    }

    struct MembershipCounts: Equatable, Decodable {
        let owners: Int
        let admins: Int
        let pickers: Int
        let total: Int
    }

    struct RemainingCapacity: Equatable, Decodable {
        let owners: Int
        let admins: Int
        let pickers: Int
    }

    let companyId: String
    let tier: Tier
    let features: FeatureFlags
    let membershipCounts: MembershipCounts
    let remainingCapacity: RemainingCapacity
}

protocol CompanyServicing {
    func updateTimezone(companyId: String, timezoneIdentifier: String, credentials: AuthCredentials) async throws -> CompanyInfo
    func updateLocation(companyId: String, address: String?, credentials: AuthCredentials) async throws -> CompanyInfo
    func fetchFeatures(companyId: String, credentials: AuthCredentials) async throws -> CompanyFeatures
}

enum CompanyServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case unauthorized
    case forbidden
    case notFound
    case invalidTimezone
    case invalidLocation

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't reach RunDaddy right now. Please try again."
        case let .serverError(code):
            return "Updating the company failed with an unexpected error (code \(code))."
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .forbidden:
            return "You don't have permission to update this company."
        case .notFound:
            return "We couldn't find that company."
        case .invalidTimezone:
            return "That timezone is not valid."
        case .invalidLocation:
            return "Please pick a valid address."
        }
    }
}

final class CompanyService: CompanyServicing {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchFeatures(companyId: String, credentials: AuthCredentials) async throws -> CompanyFeatures {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("companies")
        url.appendPathComponent(companyId)
        url.appendPathComponent("features")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompanyServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try decoder.decode(CompanyFeatures.self, from: data)
        case 401:
            throw CompanyServiceError.unauthorized
        case 403:
            throw CompanyServiceError.forbidden
        case 404:
            throw CompanyServiceError.notFound
        default:
            throw CompanyServiceError.serverError(code: httpResponse.statusCode)
        }
    }

    func updateTimezone(companyId: String, timezoneIdentifier: String, credentials: AuthCredentials) async throws -> CompanyInfo {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("companies")
        url.appendPathComponent(companyId)
        url.appendPathComponent("timezone")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["timeZone": timezoneIdentifier])

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompanyServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            let payload = try decoder.decode(CompanyResponse.self, from: data)
            return payload.company
        case 400:
            throw CompanyServiceError.invalidTimezone
        case 401:
            throw CompanyServiceError.unauthorized
        case 403:
            throw CompanyServiceError.forbidden
        case 404:
            throw CompanyServiceError.notFound
        default:
            throw CompanyServiceError.serverError(code: httpResponse.statusCode)
        }
    }

    func updateLocation(companyId: String, address: String?, credentials: AuthCredentials) async throws -> CompanyInfo {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("companies")
        url.appendPathComponent(companyId)
        url.appendPathComponent("location")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trimmedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body: [String: Any] = [
            "location": trimmedAddress.isEmpty ? NSNull() : trimmedAddress
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompanyServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            let payload = try decoder.decode(CompanyResponse.self, from: data)
            return payload.company
        case 400:
            throw CompanyServiceError.invalidLocation
        case 401:
            throw CompanyServiceError.unauthorized
        case 403:
            throw CompanyServiceError.forbidden
        case 404:
            throw CompanyServiceError.notFound
        default:
            throw CompanyServiceError.serverError(code: httpResponse.statusCode)
        }
    }
}

private struct CompanyResponse: Decodable {
    let company: CompanyInfo
}
