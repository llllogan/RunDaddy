//
//  AuthCredentials.swift
//  PickAgent
//
//  Created by ChatGPT on 3/15/2025.
//

import Foundation

struct AuthCredentials: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let userID: String
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }
}

