import Foundation

protocol MachinesServicing {
    func getMachine(id: String) async throws -> Machine
    func getMachineStats(id: String, period: SkuPeriod) async throws -> MachineStatsResponse
}

final class MachinesService: MachinesServicing {
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
    
    func getMachine(id: String) async throws -> Machine {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }
        
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("machines")
        url.appendPathComponent(id)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MachinesServiceError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw MachinesServiceError.machineNotFound
            }
            throw MachinesServiceError.serverError(code: httpResponse.statusCode)
        }
        
        return try decoder.decode(Machine.self, from: data)
    }

    func getMachineStats(id: String, period: SkuPeriod) async throws -> MachineStatsResponse {
        guard let credentials = credentialStore.loadCredentials() else {
            throw AuthError.unauthorized
        }

        var url = AppConfig.apiBaseURL
        url.appendPathComponent("machines")
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
            throw MachinesServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw MachinesServiceError.machineNotFound
            }
            throw MachinesServiceError.serverError(code: httpResponse.statusCode)
        }

        return try decoder.decode(MachineStatsResponse.self, from: data)
    }
}

enum MachinesServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case machineNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't connect to RunDaddy right now. Please try again."
        case let .serverError(code):
            return "Fetching machine failed with an unexpected error (code \(code))."
        case .machineNotFound:
            return "We couldn't find that machine. It may have been removed."
        }
    }
}
