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

struct UserProfile: Equatable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let phone: String?
    let role: String?

    var displayName: String {
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = [trimmedFirst, trimmedLast]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return fullName.isEmpty ? email : fullName
    }
}

struct CurrentUserProfile: Equatable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let phone: String?
    let role: String?
    let companies: [CompanyInfo]
    let currentCompany: CompanyInfo?

    var displayName: String {
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = [trimmedFirst, trimmedLast]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return fullName.isEmpty ? email : fullName
    }
    
    var hasCompany: Bool {
        !companies.isEmpty
    }
}

struct CompanyInfo: Codable, Equatable {
    let id: String
    let name: String
    let role: String
    let timeZone: String?
}

struct AuthSession: Equatable {
    let credentials: AuthCredentials
    let profile: UserProfile
}
