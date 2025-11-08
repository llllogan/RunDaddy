//
//  InviteCodeGeneratorViewModel.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import Foundation
import Combine

@MainActor
class InviteCodeGeneratorViewModel: ObservableObject {
    @Published var selectedRole: UserRole?
    @Published var isGenerating = false
    @Published var generatedInviteCode: InviteCode?
    @Published var errorMessage: String?
    @Published var hasPermission = false
    
    private let inviteCodesService: InviteCodesServicing
    private let authService: AuthServicing
    private var cancellables = Set<AnyCancellable>()
    
    init(
        inviteCodesService: InviteCodesServicing = InviteCodesService(),
        authService: AuthServicing = AuthService.shared
    ) {
        self.inviteCodesService = inviteCodesService
        self.authService = authService
    }
    
    func checkPermissions(companyId: String) {
        Task {
            do {
                let credentials = try await authService.getCredentials()
                let inviteCodes = try await inviteCodesService.fetchInviteCodes(
                    for: companyId,
                    credentials: credentials
                )
                // If we can fetch invite codes, user has permission
                hasPermission = true
            } catch {
                if error is InviteCodesServiceError {
                    hasPermission = false
                    errorMessage = "You don't have permission to generate invite codes for this company."
                } else {
                    errorMessage = "Failed to check permissions: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func generateInviteCode(companyId: String) {
        guard let role = selectedRole else {
            errorMessage = "Please select a role for the new user"
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        Task {
            do {
                let credentials = try await authService.getCredentials()
                let inviteCode = try await inviteCodesService.generateInviteCode(
                    companyId: companyId,
                    role: role,
                    credentials: credentials
                )
                
                generatedInviteCode = inviteCode
                isGenerating = false
            } catch {
                isGenerating = false
                if let inviteError = error as? InviteCodesServiceError {
                    errorMessage = inviteError.localizedDescription
                } else if let authError = error as? AuthError {
                    errorMessage = authError.localizedDescription
                } else {
                    errorMessage = "Failed to generate invite code: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func reset() {
        selectedRole = nil
        generatedInviteCode = nil
        errorMessage = nil
        isGenerating = false
    }
}