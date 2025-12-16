//
//  AppVersion.swift
//  PickAgent
//
//  Created by ChatGPT on 3/5/2026.
//

import Foundation

enum AppVersion {
    static let headerField = "X-App-Version"
    /// Update this constant to the required client version. No plist or env indirection.
    static let current = "17"
}

struct AppUpdateRequiredError: LocalizedError, Equatable {
    let requiredVersion: String

    var errorDescription: String? {
        "Please update the app to version \(requiredVersion) to continue."
    }
}

protocol ApiVersionValidating {
    func validate(response: HTTPURLResponse) throws
}

final class ApiVersionValidator: ApiVersionValidating {
    private var hasValidated = false

    func validate(response: HTTPURLResponse) throws {
        guard !hasValidated else { return }

        guard let serverVersion = response
            .value(forHTTPHeaderField: AppVersion.headerField)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !serverVersion.isEmpty else { return }

        if serverVersion != AppVersion.current {
            throw AppUpdateRequiredError(requiredVersion: serverVersion)
        }

        hasValidated = true
    }
}
