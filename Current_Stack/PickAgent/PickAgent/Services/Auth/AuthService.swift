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
}

final class AuthService: AuthServicing {
    private enum Endpoint {
        static let login = "auth/login"
        static let refresh = "auth/refresh"
    }
    
    private enum AuthContext: String {
        case app = "APP"
    }

    private let credentialStore: CredentialStoring
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        credentialStore: CredentialStoring = CredentialStore(),
        urlSession: URLSession = .shared
    ) {
        self.credentialStore = credentialStore
        self.urlSession = urlSession
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
