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
    
    init(authService: AuthServicing, inviteCodesService: InviteCodesServicing = InviteCodesService()) {
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
    
    func leaveCompany() async {
        guard let company = currentCompany else {
            errorMessage = "No company to leave"
            return
        }
        
        guard let credentials = authService.loadStoredCredentials() else {
            errorMessage = "Not authenticated"
            return
        }
        
        isLeavingCompany = true
        errorMessage = nil
        
        do {
            print("🔄 Leaving company: \(company.name) (ID: \(company.id))")
            try await inviteCodesService.leaveCompany(companyId: company.id, credentials: credentials)
            print("✅ Successfully left company")
            
            // Refresh auth state to update user's company context
            let refreshedCredentials = try await authService.refresh(using: credentials)
            print("✅ Auth tokens refreshed")
            
            // Store the refreshed credentials
            authService.store(credentials: refreshedCredentials)
            
            // Reload user info to reflect the change
            await loadUserInfo()
            print("✅ User info reloaded")
            
        } catch {
            print("❌ Error leaving company: \(error)")
            if let inviteError = error as? InviteCodesServiceError {
                errorMessage = inviteError.localizedDescription
            } else if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else {
                errorMessage = "Failed to leave company: \(error.localizedDescription)"
            }
        }
        
        isLeavingCompany = false
    }
}

