//
//  AuthService.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation

struct LoginRequest: Codable {
    let email: String
    let password: String
    let context: String = "MOBILE"
}

struct LoginResponse: Codable {
    struct Company: Codable {
        let id: String
        let name: String
    }
    struct User: Codable {
        let id: String
        let email: String
        let firstName: String
        let lastName: String
        let role: String
        let phone: String?
    }
    struct Tokens: Codable {
        let accessToken: String
        let refreshToken: String
        let accessTokenExpiresAt: String
        let refreshTokenExpiresAt: String
        let context: String
    }
    let company: Company
    let user: User
    let tokens: Tokens
}

class AuthService {
    static let shared = AuthService()
    private let baseURL = "http://localhost:3000" // TODO: Make configurable
    private let userDefaults = UserDefaults.standard

    private init() {}

    func login(email: String, password: String) async throws -> LoginResponse {
        let url = URL(string: "\(baseURL)/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = LoginRequest(email: email, password: password)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
        saveTokens(loginResponse.tokens)
        return loginResponse
    }

    private func saveTokens(_ tokens: LoginResponse.Tokens) {
        userDefaults.set(tokens.accessToken, forKey: "accessToken")
        userDefaults.set(tokens.refreshToken, forKey: "refreshToken")
        userDefaults.set(tokens.accessTokenExpiresAt, forKey: "accessTokenExpiresAt")
        userDefaults.set(tokens.refreshTokenExpiresAt, forKey: "refreshTokenExpiresAt")
    }

    func getAccessToken() -> String? {
        return userDefaults.string(forKey: "accessToken")
    }

    func isLoggedIn() -> Bool {
        guard let token = getAccessToken(), let expiresAt = userDefaults.string(forKey: "accessTokenExpiresAt") else {
            return false
        }
        let dateFormatter = ISO8601DateFormatter()
        guard let expiryDate = dateFormatter.date(from: expiresAt) else {
            return false
        }
        return Date() < expiryDate
    }

    func logout() {
        userDefaults.removeObject(forKey: "accessToken")
        userDefaults.removeObject(forKey: "refreshToken")
        userDefaults.removeObject(forKey: "accessTokenExpiresAt")
        userDefaults.removeObject(forKey: "refreshTokenExpiresAt")
    }
}