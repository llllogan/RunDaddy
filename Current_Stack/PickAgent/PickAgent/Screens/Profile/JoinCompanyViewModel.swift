//
//  JoinCompanyViewModel.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import Foundation
import Combine

@MainActor
class JoinCompanyViewModel: ObservableObject {
    @Published var manualCode = ""
    @Published var isJoining = false
    @Published var joinedMembership: Membership?
    @Published var errorMessage: String?
    
    private let inviteCodesService: InviteCodesServicing
    private let authService: AuthServicing
    private var cancellables = Set<AnyCancellable>()
    
    init(
        inviteCodesService: InviteCodesServicing,
        authService: AuthServicing
    ) {
        self.inviteCodesService = inviteCodesService
        self.authService = authService
    }
    
    func joinWithQRCode(_ code: String) {
        joinWithCode(code.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    func joinWithManualCode() {
        joinWithCode(manualCode.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private func joinWithCode(_ code: String) {
        guard !code.isEmpty else {
            errorMessage = "Please enter an invite code"
            return
        }
        
        isJoining = true
        errorMessage = nil
        
        Task {
            do {
                guard let credentials = authService.loadStoredCredentials() else {
                    throw AuthError.unauthorized
                }
                let membership = try await inviteCodesService.useInviteCode(
                    code,
                    credentials: credentials
                )
                
                joinedMembership = membership
                isJoining = false
                
                // Refresh auth state to update user's company context
                _ = try await authService.refresh(using: credentials)
                
            } catch {
                isJoining = false
                if let inviteError = error as? InviteCodesServiceError {
                    errorMessage = inviteError.localizedDescription
                } else if let authError = error as? AuthError {
                    errorMessage = authError.localizedDescription
                } else {
                    errorMessage = "Failed to join company: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func reset() {
        manualCode = ""
        joinedMembership = nil
        errorMessage = nil
        isJoining = false
    }
}