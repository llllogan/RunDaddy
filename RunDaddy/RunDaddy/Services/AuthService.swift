//
//  AuthService.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import Foundation

class AuthService {
    private let baseURL = "https://rundaddy.app/api" // TODO: Configure for production

    func login(email: String, password: String) async throws -> AuthContext {
        let url = URL(string: "\(baseURL)/auth/login")!
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

    func logout() {
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
}
