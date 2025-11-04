//
//  PreviewAuthService.swift
//  PickAgent
//
//  Created by Logan Janssen on 4/11/2025.
//

import Foundation
import Combine

final class PreviewAuthService: AuthServicing {
    private var storedCredentials: AuthCredentials?
    private var storedProfile: UserProfile

    init() {
        let profile = UserProfile(
            id: UUID().uuidString,
            email: "preview@example.com",
            firstName: "Preview",
            lastName: "User",
            phone: "555-867-5309",
            role: "OWNER"
        )
        storedProfile = profile
        storedCredentials = AuthCredentials(
            accessToken: "preview.access.token",
            refreshToken: "preview.refresh.token",
            userID: profile.id,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    func loadStoredCredentials() -> AuthCredentials? {
        storedCredentials
    }

    func store(credentials: AuthCredentials) {
        storedCredentials = credentials
    }

    func clearStoredCredentials() {
        storedCredentials = nil
    }

    func refresh(using credentials: AuthCredentials) async throws -> AuthCredentials {
        let refreshedCredentials = AuthCredentials(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            userID: credentials.userID,
            expiresAt: Date().addingTimeInterval(3600)
        )
        storedCredentials = refreshedCredentials
        return refreshedCredentials
    }

    func login(email: String, password: String) async throws -> AuthCredentials {
        let normalizedEmail = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if !normalizedEmail.isEmpty {
            storedProfile = UserProfile(
                id: storedProfile.id,
                email: normalizedEmail,
                firstName: storedProfile.firstName,
                lastName: storedProfile.lastName,
                phone: storedProfile.phone,
                role: storedProfile.role
            )
        }

        let credentials = AuthCredentials(
            accessToken: "preview.access.token",
            refreshToken: "preview.refresh.token",
            userID: storedProfile.id,
            expiresAt: Date().addingTimeInterval(3600)
        )

        storedCredentials = credentials
        return credentials
    }

    func fetchProfile(userID: String, credentials: AuthCredentials) async throws -> UserProfile {
        storedProfile
    }
}
