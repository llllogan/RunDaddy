//
//  AuthService.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import Foundation

class AuthService {
    func login(email: String, password: String) async throws -> AuthContext {
        let url = URL(string: "\(APIConfig.baseURL)/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "password": password,
            "context": "APP"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 412 {
            // Multiple companies, but for APP, assume default or handle later
            throw AuthError.multipleCompanies
        }

        guard httpResponse.statusCode == 200 else {
            throw AuthError.loginFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loginResponse = try decoder.decode(LoginResponse.self, from: data)

        let user = User(id: loginResponse.user.id, email: loginResponse.user.email, firstName: loginResponse.user.firstName, lastName: loginResponse.user.lastName, role: loginResponse.user.role, phone: loginResponse.user.phone)
        let company = Company(id: loginResponse.company.id, name: loginResponse.company.name)

        guard let accessToken = loginResponse.accessToken,
              let refreshToken = loginResponse.refreshToken,
              let accessExpires = loginResponse.accessTokenExpiresAt,
              let refreshExpires = loginResponse.refreshTokenExpiresAt,
              let context = loginResponse.context else {
            throw AuthError.invalidResponse
        }

        return AuthContext(user: user, company: company, accessToken: accessToken, refreshToken: refreshToken, accessTokenExpiresAt: accessExpires, refreshTokenExpiresAt: refreshExpires, context: context)
    }

    func logout() async {
        // Call logout API endpoint
        if let auth = getStoredAuth() {
            let url = URL(string: "\(APIConfig.baseURL)/auth/logout")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")

            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                // Ignore logout API errors
            }
        }

        // Clear stored auth
        UserDefaults.standard.removeObject(forKey: "authContext")
    }

    func getStoredAuth() -> AuthContext? {
        guard let data = UserDefaults.standard.data(forKey: "authContext") else { return nil }
        return try? JSONDecoder().decode(AuthContext.self, from: data)
    }

    func storeAuth(_ auth: AuthContext) {
        let data = try? JSONEncoder().encode(auth)
        UserDefaults.standard.set(data, forKey: "authContext")
    }

    func refreshToken() async throws -> AuthContext {
        guard let auth = getStoredAuth() else {
            throw AuthError.notLoggedIn
        }

        let url = URL(string: "\(APIConfig.baseURL)/auth/refresh")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(auth.refreshToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            throw AuthError.refreshFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let refreshResponse = try decoder.decode(LoginResponse.self, from: data)

        let newAuth = AuthContext(user: auth.user, company: auth.company, accessToken: refreshResponse.accessToken ?? auth.accessToken, refreshToken: refreshResponse.refreshToken ?? auth.refreshToken, accessTokenExpiresAt: refreshResponse.accessTokenExpiresAt ?? auth.accessTokenExpiresAt, refreshTokenExpiresAt: refreshResponse.refreshTokenExpiresAt ?? auth.refreshTokenExpiresAt, context: auth.context)
        storeAuth(newAuth)
        return newAuth
    }

    func getValidToken() async throws -> String {
        guard var auth = getStoredAuth() else {
            throw AuthError.notLoggedIn
        }

        if auth.accessTokenExpiresAt < Date() {
            do {
                auth = try await refreshToken()
            } catch AuthError.refreshFailed {
                // Refresh failed, likely due to 401, logout
                await logout()
                throw AuthError.unauthorized
            }
        }

        return auth.accessToken
    }

    func performAuthenticatedRequest(_ request: URLRequest, retryOn401: Bool = true) async throws -> (Data, HTTPURLResponse) {
        let token = try await getValidToken()

        var authenticatedRequest = request
        authenticatedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: authenticatedRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 401 && retryOn401 {
            // Try to refresh token and retry once
            do {
                _ = try await refreshToken()
                // Retry the request (without further retries to prevent loops)
                return try await performAuthenticatedRequest(request, retryOn401: false)
            } catch {
                // Refresh failed, logout
                await logout()
                throw AuthError.unauthorized
            }
        } else if httpResponse.statusCode == 401 {
            // Already tried refresh, logout
            await logout()
            throw AuthError.unauthorized
        }

        return (data, httpResponse)
    }
}

struct LoginResponse: Codable {
    let user: User
    let company: Company
    let accessToken: String?
    let refreshToken: String?
    let accessTokenExpiresAt: Date?
    let refreshTokenExpiresAt: Date?
    let context: String?
}

enum AuthError: Error {
    case invalidResponse
    case loginFailed
    case multipleCompanies
    case notLoggedIn
    case refreshFailed
    case unauthorized
}
