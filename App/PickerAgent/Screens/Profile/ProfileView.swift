//
//  ProfileView.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = ProfileViewModel(
        authService: AuthService(),
        inviteCodesService: InviteCodesService()
    )
    @State private var showInviteGenerator = false
    @State private var showJoinCompany = false
    @State private var showLeaveCompanyConfirmation = false
    @AppStorage(DirectionsApp.storageKey) private var preferredDirectionsAppRawValue = DirectionsApp.appleMaps.rawValue
    
    // Optional: For sheet presentation
    var isPresentedAsSheet: Bool = false
    var onDismiss: (() -> Void)? = nil
    var onLogout: (() -> Void)? = nil
    
    private var initials: String {
        let components = viewModel.userDisplayName.split(separator: " ")
        let firstInitial = components.first?.first
        let secondInitial = components.dropFirst().first?.first
        if let first = firstInitial, let second = secondInitial {
            return String([first, second]).uppercased()
        } else if let first = firstInitial {
            return String(first).uppercased()
        }
        return String(viewModel.userEmail.prefix(1)).uppercased()
    }
    
    private var preferredDirectionsApp: DirectionsApp {
        DirectionsApp(rawValue: preferredDirectionsAppRawValue) ?? .appleMaps
    }
    
    private var canEditCompanyLocation: Bool {
        viewModel.userRole == .owner || viewModel.userRole == .admin || viewModel.userRole == .god
    }

    private func roleDisplay(for company: CompanyInfo) -> String {
        if let role = UserRole(rawValue: company.role.uppercased()) {
            return role.displayName
        }
        return company.role.capitalized
    }
    
    var body: some View {
        NavigationStack {
            List {
                // User Info Section with enhanced styling
                Section {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Theme.blackOnWhite.opacity(0.15))
                                .frame(maxWidth: 60)

                            Text(initials)
                                .foregroundStyle(Theme.blackOnWhite)
                                .font(.title3.weight(.bold))
                        }

                        VStack(alignment: .leading) {
                            Text(viewModel.userDisplayName)
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text(viewModel.userEmail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Text(viewModel.userRole.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if !viewModel.companies.isEmpty {
                        Menu {
                            ForEach(viewModel.companies, id: \.id) { company in
                                Button {
                                    Task {
                                        let didSwitch = await viewModel.switchCompany(to: company)
                                        if didSwitch {
                                            await authViewModel.refreshSessionFromStoredCredentials()
                                        }
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(company.name)
                                                .foregroundStyle(.primary)
                                            Text(roleDisplay(for: company))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if company.id == viewModel.currentCompany?.id {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Theme.blackOnWhite)
                                        }
                                    }
                                }
                                .disabled(viewModel.isSwitchingCompany || company.id == viewModel.currentCompany?.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "person.2.circle")
                                    .foregroundStyle(.indigo)
                                Text("Company")
                                Spacer()
                                if viewModel.isSwitchingCompany {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    HStack(spacing: 6) {
                                        Text(viewModel.currentCompany?.name ?? "Select Company")
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isSwitchingCompany)
                    }
                }
                
                // No Company State
                if viewModel.currentCompany == nil {
                    NoCompanyMembershipSection {
                        showJoinCompany = true
                    }
                }

                // Navigation preference section
                Section(header: Text("Settings"), footer: Text("Runs and analytics will be generated in this timezone for the company.")) {
                    Menu {
                        ForEach(DirectionsApp.allCases) { app in
                            Button {
                                preferredDirectionsAppRawValue = app.rawValue
                            } label: {
                                HStack {
                                    Text(app.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "map")
                                .foregroundStyle(.cyan)
                            Text("Navigation App")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(preferredDirectionsApp.displayName)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary)
                    
                    if let company = viewModel.currentCompany {
                        NavigationLink {
                            CompanyTimezonePickerView(
                                company: company,
                                selectedIdentifier: viewModel.companyTimezoneIdentifier,
                                onSelect: { identifier in
                                    viewModel.updateTimezone(for: company.id, to: identifier)
                                }
                            )
                        } label: {
                            HStack {
                                Image(systemName: "globe.badge.clock")
                                    .foregroundStyle(.purple)
                                Text("Timezone")
                                Spacer()
                                Text(viewModel.companyTimezoneDisplayName)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        if canEditCompanyLocation {
                            NavigationLink {
                                CompanyLocationPickerView(
                                    viewModel: viewModel,
                                    company: company,
                                    showsCancel: false
                                )
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(.red)
                                    Text("Company Location")
                                    Spacer()
                                    Text(viewModel.companyLocationAddress.isEmpty ? "Add address" : viewModel.companyLocationAddress)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .disabled(viewModel.isUpdatingLocation)
                        }
                    }
                }
                
                // Company Actions Section
                if viewModel.currentCompany != nil {
                    Section {
                        let inviteActionAllowed = viewModel.userRole == .god || viewModel.userRole == .admin || viewModel.userRole == .owner
                        if inviteActionAllowed {
                            let hasCapacity = viewModel.inviteRoleCapacities.contains { $0.remaining > 0 }

                            Button(action: {
                                showInviteGenerator = true
                            }) {
                                HStack {
                                    Image(systemName: "qrcode")
                                        .foregroundColor(hasCapacity ? .blue : .gray)
                                    Text("Generate Invite Code")
                                        .foregroundStyle(hasCapacity ? .primary : .secondary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasCapacity)
                        }
                        
                        Button(action: {
                            showJoinCompany = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.green)
                                Text("Join Another Company")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Settings Section
                Section("Danger Zone") {
                    if viewModel.currentCompany != nil {
                        Button(action: {
                            showLeaveCompanyConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "person.badge.minus")
                                    .foregroundColor(.orange)
                                Text("Leave Company")
                                    .foregroundColor(.orange)
                                Spacer()
                                if viewModel.isLeavingCompany {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        .disabled(viewModel.isLeavingCompany)
                    }
                    
                    Button(action: {
                        // Use the logout callback if provided, otherwise fall back to viewModel logout
                        if let onLogout = onLogout {
                            onLogout()
                        } else {
                            viewModel.logout()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.square")
                                .foregroundColor(.red)
                            Text("Sign Out")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if isPresentedAsSheet {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            onDismiss?()
                        } label: {
                            Label("Done", systemImage: "xmark")
                        }
                    }
                }
            }
            .onAppear {
                viewModel.loadUserInfo()
            }
            .refreshable {
                viewModel.loadUserInfo()
            }
            .sheet(isPresented: $showInviteGenerator) {
                if let company = viewModel.currentCompany {
                    InviteCodeGeneratorView(
                        companyId: company.id,
                        companyName: company.name,
                        roleCapacities: viewModel.inviteRoleCapacities
                    )
                }
            }
            .fullScreenCover(isPresented: $showJoinCompany) {
                JoinCompanyScannerView {
                    Task {
                        await authViewModel.refreshSessionFromStoredCredentials()
                        viewModel.loadUserInfo()
                    }
                }
            }
            .alert("Are you sure?", isPresented: $showLeaveCompanyConfirmation) {
                Button("Leave Company", role: .destructive) {
                    Task {
                        let success = await viewModel.leaveCompany()
                        if success {
                            await authViewModel.refreshSessionFromStoredCredentials()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You cannot undo this action.")
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
}

// MARK: - Profile Info Components

private struct ProfileInfoRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel(service: PreviewAuthService()))
}
