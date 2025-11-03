//
//  AuthContext.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import Foundation

struct User: Codable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let role: String
    let phone: String?
}

struct Company: Codable {
    let id: String
    let name: String
}

struct AuthContext: Codable {
    let user: User
    let company: Company
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date
    let refreshTokenExpiresAt: Date
    let context: String
}