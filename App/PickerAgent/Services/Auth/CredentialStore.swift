//
//  CredentialStore.swift
//  PickAgent
//
//  Created by ChatGPT on 3/15/2025.
//

import Foundation

protocol CredentialStoring {
    func loadCredentials() -> AuthCredentials?
    func save(credentials: AuthCredentials)
    func clear()
}

final class CredentialStore: CredentialStoring {
    private let storeKey = "com.rundaddy.pickagent.credentials"
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func loadCredentials() -> AuthCredentials? {
        guard let data = userDefaults.data(forKey: storeKey) else {
            return nil
        }

        do {
            return try decoder.decode(AuthCredentials.self, from: data)
        } catch {
            // Failed decode likely means the stored payload is outdated; clear to prevent repeated failures.
            userDefaults.removeObject(forKey: storeKey)
            return nil
        }
    }

    func save(credentials: AuthCredentials) {
        do {
            let data = try encoder.encode(credentials)
            userDefaults.set(data, forKey: storeKey)
        } catch {
            // Silently drop malformed payload because we cannot persist it safely.
        }
    }

    func clear() {
        userDefaults.removeObject(forKey: storeKey)
    }
}

