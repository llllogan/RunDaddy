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
    
    private let authService: AuthServicing
    private var cancellables = Set<AnyCancellable>()
    
    init(authService: AuthServicing = AuthService.shared) {
        self.authService = authService
    }
    
    func loadUserInfo() {
        Task {
            do {
                let credentials = try await authService.getCredentials()
                let profile = try await authService.getProfile()
                
                await MainActor.run {
                    userDisplayName = profile.displayName
                    userEmail = profile.email
                    
                    if let roleString = profile.role, let role = UserRole(rawValue: roleString.uppercased()) {
                        userRole = role
                        canGenerateInvites = (role == .admin || role == .owner)
                    }
                    
                    // TODO: Load current company info from runs service or new endpoint
                    // For now, we'll use a placeholder
                    if profile.hasCompany {
                        currentCompany = CompanyInfo(id: "company-1", name: "Current Company")
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load user info: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func logout() {
        Task {
            do {
                try await authService.logout()
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to logout: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct CompanyInfo: Equatable {
    let id: String
    let name: String
}