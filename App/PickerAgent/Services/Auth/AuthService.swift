//
//  AuthService.swift
//  PickAgent
//
//  Created by ChatGPT on 3/15/2025.
//

import Foundation

protocol AuthServicing {
    func loadStoredCredentials() -> AuthCredentials?
    func store(credentials: AuthCredentials)
    func clearStoredCredentials()
    func refresh(using credentials: AuthCredentials) async throws -> AuthCredentials
    func login(email: String, password: String) async throws -> AuthCredentials
    func signup(email: String, password: String, firstName: String, lastName: String, phone: String?) async throws -> AuthCredentials
    func fetchProfile(userID: String, credentials: AuthCredentials) async throws -> UserProfile
    func fetchCurrentUserProfile(credentials: AuthCredentials) async throws -> CurrentUserProfile
    func switchCompany(companyId: String, credentials: AuthCredentials) async throws -> AuthCredentials
}

final class AuthService: AuthServicing {
    private enum Endpoint {
        static let login = "auth/login"
        static let signup = "auth/signup"
        static let refresh = "auth/refresh"
    }
    
    private enum AuthContext: String {
        case app = "APP"
    }

    private let credentialStore: CredentialStoring
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let versionValidator: ApiVersionValidating

    init(
        credentialStore: CredentialStoring = CredentialStore(),
        urlSession: URLSession = .shared,
        versionValidator: ApiVersionValidating = ApiVersionValidator()
    ) {
        self.credentialStore = credentialStore
        self.urlSession = urlSession
        self.versionValidator = versionValidator
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadStoredCredentials() -> AuthCredentials? {
        credentialStore.loadCredentials()
    }

    func store(credentials: AuthCredentials) {
        credentialStore.save(credentials: credentials)
    }

    func clearStoredCredentials() {
        credentialStore.clear()
    }

    func refresh(using credentials: AuthCredentials) async throws -> AuthCredentials {
        let response: AuthPayload = try await performRequest(
            path: Endpoint.refresh,
            body: RefreshRequest(refreshToken: credentials.refreshToken)
        )

        return response.buildCredentials()
    }

    func login(email: String, password: String) async throws -> AuthCredentials {
        let response: AuthPayload = try await performRequest(
            path: Endpoint.login,
            body: LoginRequest(email: email, password: password, context: AuthContext.app.rawValue)
        )

        return response.buildCredentials()
    }

    func signup(email: String, password: String, firstName: String, lastName: String, phone: String?) async throws -> AuthCredentials {
        let response: AuthPayload = try await performRequest(
            path: Endpoint.signup,
            body: SignupRequest(
                userEmail: email,
                userPassword: password,
                userFirstName: firstName,
                userLastName: lastName,
                userPhone: phone
            )
        )

        return response.buildCredentials()
    }

    func fetchCurrentUserProfile(credentials: AuthCredentials) async throws -> CurrentUserProfile {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("auth")
        url.appendPathComponent("me")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        try validateVersion(in: httpResponse)
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            throw AuthError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(CurrentUserProfileResponse.self, from: data)
        return payload.profile
    }

    func switchCompany(companyId: String, credentials: AuthCredentials) async throws -> AuthCredentials {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("auth")
        url.appendPathComponent("switch-company")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "companyId": companyId,
            "context": AuthContext.app.rawValue,
            "persist": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        try validateVersion(in: httpResponse)

        guard (200..<300).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401:
                throw SwitchCompanyError.unauthorized
            case 403:
                throw SwitchCompanyError.notAllowed
            case 404:
                throw SwitchCompanyError.membershipNotFound
            default:
                throw SwitchCompanyError.serverError(code: httpResponse.statusCode)
            }
        }

        let payload = try decoder.decode(SwitchCompanyResponse.self, from: data)
        return payload.buildCredentials()
    }
    
    func fetchProfile(userID: String, credentials: AuthCredentials) async throws -> UserProfile {
        // Try standalone profile endpoint first (for users without companies)
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("auth")
        url.appendPathComponent("profile")
        url.appendPathComponent(userID)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            try validateVersion(in: httpResponse)

            if httpResponse.statusCode == 404 {
                // If standalone endpoint returns 404, try regular users endpoint
                return try await fetchProfileFromUsersEndpoint(userID: userID, credentials: credentials)
            }
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 {
                    throw AuthError.unauthorized
                }
                throw AuthError.serverError(code: httpResponse.statusCode)
            }

            let payload = try decoder.decode(StandaloneUserResponse.self, from: data)
            return payload.profile
        } catch {
            // If standalone endpoint fails, try the regular users endpoint
            return try await fetchProfileFromUsersEndpoint(userID: userID, credentials: credentials)
        }
    }
    
    private func fetchProfileFromUsersEndpoint(userID: String, credentials: AuthCredentials) async throws -> UserProfile {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("users")
        url.appendPathComponent(userID)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        try validateVersion(in: httpResponse)

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            throw AuthError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(UserResponse.self, from: data)
        return payload.profile
    }

    private func validateVersion(in response: HTTPURLResponse) throws {
        try versionValidator.validate(response: response)
    }

    private func performRequest<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request
    ) async throws -> Response {
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        request.httpShouldHandleCookies = true

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        try validateVersion(in: httpResponse)

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            throw AuthError.serverError(code: httpResponse.statusCode)
        }

        return try decoder.decode(Response.self, from: data)
    }
}

private struct LoginRequest: Encodable {
    let email: String
    let password: String
    let context: String
}

private struct SignupRequest: Encodable {
    let userEmail: String
    let userPassword: String
    let userFirstName: String
    let userLastName: String
    let userPhone: String?
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
}

private struct AuthPayload: Decodable {
    struct UserSummary: Decodable {
        let id: String
    }

    let user: UserSummary
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date?
    let refreshTokenExpiresAt: Date?

    func buildCredentials(currentDate: Date = .now) -> AuthCredentials {
        let expirationDate = accessTokenExpiresAt ?? currentDate.addingTimeInterval(3600)

        return AuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userID: user.id,
            expiresAt: expirationDate
        )
    }
}

private struct SwitchCompanyResponse: Decodable {
    struct SessionUser: Decodable {
        let id: String
    }

    let user: SessionUser
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date?
    let refreshTokenExpiresAt: Date?

    func buildCredentials(currentDate: Date = .now) -> AuthCredentials {
        let expirationDate = accessTokenExpiresAt ?? currentDate.addingTimeInterval(3600)

        return AuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userID: user.id,
            expiresAt: expirationDate
        )
    }
}

private struct CurrentUserProfileResponse: Decodable {
    let companies: [CompanyInfo]
    let currentCompany: CompanyInfo?
    let user: UserInfo

    var profile: CurrentUserProfile {
        CurrentUserProfile(
            id: user.id,
            email: user.email,
            firstName: user.firstName,
            lastName: user.lastName,
            phone: user.phone,
            role: user.role,
            companies: companies,
            currentCompany: currentCompany
        )
    }

    func toUserProfile() -> UserProfile {
        UserProfile(
            id: user.id,
            email: user.email,
            firstName: user.firstName,
            lastName: user.lastName,
            phone: user.phone,
            role: currentCompany?.role ?? user.role
        )
    }
}

private struct UserInfo: Decodable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let phone: String?
    let role: String
}

private struct UserResponse: Decodable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let phone: String?
    let role: String?

    var profile: UserProfile {
        UserProfile(
            id: id,
            email: email,
            firstName: firstName,
            lastName: lastName,
            phone: phone,
            role: role
        )
    }
}

private struct StandaloneUserResponse: Decodable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let phone: String?
    let role: String?

    var profile: UserProfile {
        UserProfile(
            id: id,
            email: email,
            firstName: firstName,
            lastName: lastName,
            phone: phone,
            role: role
        )
    }
}

extension CurrentUserProfile {
    func toUserProfile() -> UserProfile {
        UserProfile(
            id: id,
            email: email,
            firstName: firstName,
            lastName: lastName,
            phone: phone,
            role: currentCompany?.role ?? role
        )
    }
}

enum AuthError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We could not reach RunDaddy right now. Please try again."
        case let .serverError(code):
            if code == 401 {
                return "Your session expired. Please sign in again."
            }
            return "Server responded with an unexpected error (code \(code))."
        case .unauthorized:
            return "Your email address or password is incorrect."
        }
    }
}

enum SwitchCompanyError: LocalizedError {
    case unauthorized
    case membershipNotFound
    case notAllowed
    case serverError(code: Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .membershipNotFound:
            return "We couldn't find that company in your memberships."
        case .notAllowed:
            return "Your role doesn't allow switching to that company."
        case let .serverError(code):
            return "Switching companies failed with an unexpected error (code \(code))."
        }
    }
}
