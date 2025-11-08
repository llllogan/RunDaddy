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

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading):
                return true
            case let (.authenticated(lhsSession), .authenticated(rhsSession)):
                return lhsSession == rhsSession
            case let (.login(lhsMessage), .login(rhsMessage)):
                return lhsMessage == rhsMessage
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
            let profile = try await service.fetchProfile(userID: refreshedCredentials.userID, credentials: refreshedCredentials)
            let session = AuthSession(credentials: refreshedCredentials, profile: profile)
            service.store(credentials: refreshedCredentials)
            phase = .authenticated(session)
        } catch {
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

        do {
            let normalizedEmail = email
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let credentials = try await service.login(email: normalizedEmail, password: password)
            let profile = try await service.fetchProfile(userID: credentials.userID, credentials: credentials)
            let session = AuthSession(credentials: credentials, profile: profile)
            service.store(credentials: credentials)
            phase = .authenticated(session)
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else {
                errorMessage = "Something went wrong while signing in. Please try again."
            }
        }

        isProcessing = false
    }

    func createAccount(email: String, password: String, firstName: String, lastName: String, phone: String?) async {
        guard !isProcessing else { return }
        errorMessage = nil
        isProcessing = true

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
            let profile = try await service.fetchProfile(userID: credentials.userID, credentials: credentials)
            let session = AuthSession(credentials: credentials, profile: profile)
            service.store(credentials: credentials)
            phase = .authenticated(session)
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else {
                errorMessage = "Something went wrong while creating your account. Please try again."
            }
        }

        isProcessing = false
    }

    func logout() {
        service.clearStoredCredentials()
        phase = .login(message: nil)
    }
}
