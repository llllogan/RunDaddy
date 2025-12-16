//
//  AuthViewModel.swift
//  PickAgent
//
//  Created by ChatGPT on 3/15/2025.
//

import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case authenticated(AuthSession)
        case login(message: String?)
        case updateRequired(requiredVersion: String)
        case maintenance

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading):
                return true
            case let (.authenticated(lhsSession), .authenticated(rhsSession)):
                return lhsSession == rhsSession
            case let (.login(lhsMessage), .login(rhsMessage)):
                return lhsMessage == rhsMessage
            case let (.updateRequired(lhsVersion), .updateRequired(rhsVersion)):
                return lhsVersion == rhsVersion
            case (.maintenance, .maintenance):
                return true
            default:
                return false
            }
        }
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var isProcessing = false
    @Published var errorMessage: String?

    private let service: AuthServicing

    init(service: AuthServicing) {
        self.service = service
    }

    convenience init() {
        self.init(service: AuthService())
    }

    func bootstrap() async {
        phase = .loading
        errorMessage = nil

        guard let storedCredentials = service.loadStoredCredentials() else {
            phase = .login(message: nil)
            return
        }

        do {
            let refreshedCredentials = try await service.refresh(using: storedCredentials)
            let currentProfile = try await service.fetchCurrentUserProfile(credentials: refreshedCredentials)
            let session = AuthSession(credentials: refreshedCredentials, profile: currentProfile.toUserProfile())
            service.store(credentials: refreshedCredentials)
            phase = .authenticated(session)
        } catch {
            if handleUpdateRequirement(from: error) {
                return
            }
            if handleMaintenanceRequirement(from: error) {
                return
            }
            service.clearStoredCredentials()
            if let authError = error as? AuthError, case .unauthorized = authError {
                phase = .login(message: "Please sign in again to continue.")
            } else {
                errorMessage = error.localizedDescription
                phase = .login(message: "We couldn't refresh your session. Please sign in again.")
            }
        }
    }

    func login(email: String, password: String) async {
        guard !isProcessing else { return }
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        do {
            let normalizedEmail = email
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let credentials = try await service.login(email: normalizedEmail, password: password)
            let currentProfile = try await service.fetchCurrentUserProfile(credentials: credentials)
            let session = AuthSession(credentials: credentials, profile: currentProfile.toUserProfile())
            service.store(credentials: credentials)
            phase = .authenticated(session)
        } catch {
            if handleUpdateRequirement(from: error) {
                return
            }
            if handleMaintenanceRequirement(from: error) {
                return
            }
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else {
                errorMessage = "Something went wrong while signing in. Please try again."
            }
        }
    }

    func createAccount(email: String, password: String, firstName: String, lastName: String, phone: String?) async {
        guard !isProcessing else { return }
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        do {
            let normalizedEmail = email
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let credentials = try await service.signup(
                email: normalizedEmail,
                password: password,
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: phone?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let currentProfile = try await service.fetchCurrentUserProfile(credentials: credentials)
            let session = AuthSession(credentials: credentials, profile: currentProfile.toUserProfile())
            service.store(credentials: credentials)
            phase = .authenticated(session)
        } catch {
            if handleUpdateRequirement(from: error) {
                return
            }
            if handleMaintenanceRequirement(from: error) {
                return
            }
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else {
                errorMessage = "Something went wrong while creating your account. Please try again."
            }
        }
    }

    func logout() {
        service.clearStoredCredentials()
        phase = .login(message: nil)
    }

    func refreshSessionFromStoredCredentials() async {
        guard let storedCredentials = service.loadStoredCredentials() else {
            phase = .login(message: nil)
            return
        }

        do {
            let currentProfile = try await service.fetchCurrentUserProfile(credentials: storedCredentials)
            let session = AuthSession(credentials: storedCredentials, profile: currentProfile.toUserProfile())
            phase = .authenticated(session)
        } catch {
            if handleUpdateRequirement(from: error) {
                return
            }
            if handleMaintenanceRequirement(from: error) {
                return
            }
            if let authError = error as? AuthError, case .unauthorized = authError {
                service.clearStoredCredentials()
                phase = .login(message: "Please sign in again to continue.")
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleUpdateRequirement(from error: Error) -> Bool {
        if let updateError = error as? AppUpdateRequiredError {
            errorMessage = nil
            isProcessing = false
            phase = .updateRequired(requiredVersion: updateError.requiredVersion)
            return true
        }

        return false
    }

    private func handleMaintenanceRequirement(from error: Error) -> Bool {
        guard isBackendConnectionFailure(error) else {
            return false
        }

        errorMessage = nil
        isProcessing = false
        phase = .maintenance
        return true
    }

    private func isBackendConnectionFailure(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return isBackendConnectionFailure(code: urlError.code)
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }

        return isBackendConnectionFailure(code: URLError.Code(rawValue: nsError.code))
    }

    private func isBackendConnectionFailure(code: URLError.Code) -> Bool {
        switch code {
        case .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .secureConnectionFailed,
             .timedOut:
            return true
        default:
            return false
        }
    }
}
