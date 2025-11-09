//
//  ProfileViewModel.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import Foundation
import Combine

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var userDisplayName = ""
    @Published var userEmail = ""
    @Published var userRole: UserRole = .picker
    @Published var currentCompany: CompanyInfo?
    @Published var canGenerateInvites = false
    @Published var errorMessage: String?
    @Published var isLeavingCompany = false
    
    let authService: AuthServicing
    private let inviteCodesService: InviteCodesServicing
    private var cancellables = Set<AnyCancellable>()
    
    init(authService: AuthServicing, inviteCodesService: InviteCodesServicing) {
        self.authService = authService
        self.inviteCodesService = inviteCodesService
    }
    
    func loadUserInfo() {
        Task {
            do {
                guard let credentials = authService.loadStoredCredentials() else {
                    throw AuthError.unauthorized
                }
                let profile = try await authService.fetchCurrentUserProfile(credentials: credentials)
                
                await MainActor.run {
                    userDisplayName = profile.displayName
                    userEmail = profile.email
                    
                    if let roleString = profile.role, let role = UserRole(rawValue: roleString.uppercased()) {
                        userRole = role
                        canGenerateInvites = (role == .admin || role == .owner)
                    }
                    
                    currentCompany = profile.currentCompany
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load user info: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func logout() {
        print("🔄 Logging out...")
        authService.clearStoredCredentials()
        print("✅ Credentials cleared")
    }
    
    func leaveCompany() async -> Bool {
        guard let company = currentCompany else {
            errorMessage = "No company to leave"
            return false
        }
        
        guard let credentials = authService.loadStoredCredentials() else {
            errorMessage = "Not authenticated"
            return false
        }
        
        isLeavingCompany = true
        errorMessage = nil
        defer {
            isLeavingCompany = false
        }
        
        do {
            print("🔄 Leaving company: \(company.name) (ID: \(company.id))")
            let result = try await inviteCodesService.leaveCompany(companyId: company.id, credentials: credentials)
            print("✅ Successfully left company")
            authService.store(credentials: result.credentials)
            
            if let updatedMembership = result.membership {
                currentCompany = CompanyInfo(
                    id: updatedMembership.companyId,
                    name: updatedMembership.company?.name ?? "Company",
                    role: updatedMembership.role.rawValue
                )
            } else {
                currentCompany = nil
            }
            
            // Reload user info to reflect the change
            loadUserInfo()
            print("✅ User info reloaded")
            return true
        } catch {
            print("❌ Error leaving company: \(error)")
            if let inviteError = error as? InviteCodesServiceError {
                if case .companyNotFound = inviteError {
                    errorMessage = "Unable to leave company. The leave company feature may not be available yet. Please contact support."
                } else {
                    errorMessage = inviteError.localizedDescription
                }
            } else if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else {
                errorMessage = "Failed to leave company: \(error.localizedDescription)"
            }
            return false
        }
    }
}
