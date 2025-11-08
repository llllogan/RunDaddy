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
    
    init(authService: AuthServicing) {
        self.authService = authService
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
        authService.clearStoredCredentials()
    }
}

