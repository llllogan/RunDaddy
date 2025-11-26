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
    @Published var companies: [CompanyInfo] = []
    @Published var canGenerateInvites = false
    @Published var companyFeatures: CompanyFeatures?
    @Published var inviteRoleCapacities: [InviteRoleCapacity] = []
    @Published var errorMessage: String?
    @Published var isLeavingCompany = false
    @Published var isSwitchingCompany = false
    @Published var companyTimezoneIdentifier: String = TimeZone.current.identifier
    @Published var companyLocationAddress: String = ""
    @Published var isUpdatingLocation = false
    
    let authService: AuthServicing
    private let inviteCodesService: InviteCodesServicing
    private let companyService = CompanyService()
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
                    }

                    currentCompany = profile.currentCompany
                    companies = profile.companies
                    companyLocationAddress = profile.currentCompany?.location ?? ""
                    companyTimezoneIdentifier = profile.currentCompany?.timeZone ?? TimeZone.current.identifier

                    if let companyId = profile.currentCompany?.id {
                        Task {
                            await self.loadCompanyFeatures(companyId: companyId)
                        }
                    } else {
                        companyFeatures = nil
                        inviteRoleCapacities = []
                        canGenerateInvites = false
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
                    role: updatedMembership.role.rawValue,
                    location: updatedMembership.company?.location,
                    timeZone: updatedMembership.company?.timeZone
                )
            } else {
                currentCompany = nil
            }
            companyLocationAddress = currentCompany?.location ?? ""
            companyTimezoneIdentifier = currentCompany?.timeZone ?? TimeZone.current.identifier
            
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

    func switchCompany(to company: CompanyInfo) async -> Bool {
        if company.id == currentCompany?.id {
            return false
        }

        guard let credentials = authService.loadStoredCredentials() else {
            errorMessage = "Not authenticated"
            return false
        }

        isSwitchingCompany = true
        errorMessage = nil

        defer {
            isSwitchingCompany = false
        }

        do {
            let updatedCredentials = try await authService.switchCompany(companyId: company.id, credentials: credentials)
            authService.store(credentials: updatedCredentials)
            loadUserInfo()
            return true
        } catch let switchError as SwitchCompanyError {
            errorMessage = switchError.localizedDescription
        } catch let authError as AuthError {
            errorMessage = authError.localizedDescription
        } catch {
            errorMessage = "Failed to switch companies: \(error.localizedDescription)"
        }

        return false
    }

    var companyTimezoneDisplayName: String {
        if let timezone = TimeZone(identifier: companyTimezoneIdentifier) {
            return timezone.localizedName(for: .standard, locale: .current)
                ?? timezone.localizedName(for: .generic, locale: .current)
                ?? timezone.identifier
        }
        return companyTimezoneIdentifier
    }

    func updateLocation(for companyId: String, to address: String?) async -> Bool {
        guard let credentials = authService.loadStoredCredentials() else {
            errorMessage = "Not authenticated"
            return false
        }

        isUpdatingLocation = true
        errorMessage = nil
        defer { isUpdatingLocation = false }

        do {
            let updatedCompany = try await companyService.updateLocation(
                companyId: companyId,
                address: address,
                credentials: credentials
            )
            companyLocationAddress = updatedCompany.location ?? ""
            currentCompany = updatedCompany
            companies = companies.map { company in
                guard company.id == updatedCompany.id else { return company }
                return updatedCompany
            }
            return true
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let companyError = error as? CompanyServiceError {
                errorMessage = companyError.localizedDescription
            } else {
                errorMessage = "Failed to update location: \(error.localizedDescription)"
            }
            return false
        }
    }

    func updateTimezone(for companyId: String, to identifier: String) {
        Task {
            do {
                guard let credentials = authService.loadStoredCredentials() else {
                    throw AuthError.unauthorized
                }
                let updatedCompany = try await companyService.updateTimezone(
                    companyId: companyId,
                    timezoneIdentifier: identifier,
                    credentials: credentials
                )
                await MainActor.run {
                    companyLocationAddress = updatedCompany.location ?? ""
                    companyTimezoneIdentifier = updatedCompany.timeZone ?? TimeZone.current.identifier
                    currentCompany = updatedCompany
                    companies = companies.map { company in
                        guard company.id == updatedCompany.id else { return company }
                        return updatedCompany
                    }
                }
            } catch {
                await MainActor.run {
                    if let authError = error as? AuthError {
                        errorMessage = authError.localizedDescription
                    } else if let companyError = error as? CompanyServiceError {
                        errorMessage = companyError.localizedDescription
                    } else {
                        errorMessage = "Failed to update timezone: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func loadCompanyFeatures(companyId: String) async {
        guard let credentials = authService.loadStoredCredentials() else {
            errorMessage = "Not authenticated"
            canGenerateInvites = false
            inviteRoleCapacities = []
            return
        }

        do {
            let features = try await companyService.fetchFeatures(companyId: companyId, credentials: credentials)
            companyFeatures = features
            rebuildInvitePermissions()
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let companyError = error as? CompanyServiceError {
                errorMessage = companyError.localizedDescription
            } else {
                errorMessage = "Failed to load company plan details: \(error.localizedDescription)"
            }
            companyFeatures = nil
            inviteRoleCapacities = []
            rebuildInvitePermissions()
        }
    }

    private func rebuildInvitePermissions() {
        let canManage = (userRole == .god || userRole == .admin || userRole == .owner)
        guard canManage, let features = companyFeatures else {
            canGenerateInvites = false
            inviteRoleCapacities = []
            return
        }

        let counts = features.membershipCounts
        let tier = features.tier

        inviteRoleCapacities = [
            InviteRoleCapacity(role: .owner, used: counts.owners, max: tier.maxOwners),
            InviteRoleCapacity(role: .admin, used: counts.admins, max: tier.maxAdmins),
            InviteRoleCapacity(role: .picker, used: counts.pickers, max: tier.maxPickers)
        ]

        canGenerateInvites = inviteRoleCapacities.contains { $0.remaining > 0 }
    }
}

struct InviteRoleCapacity: Identifiable, Equatable {
    let role: UserRole
    let used: Int
    let max: Int

    var id: UserRole { role }

    var remaining: Int {
        Swift.max(0, max - used)
    }
}
