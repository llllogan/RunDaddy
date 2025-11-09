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
    
    var body: some View {
        NavigationStack {
            List {
                // User Info Section with enhanced styling
                Section {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Theme.packageBrown.opacity(0.15))
                                .frame(maxWidth: 60)

                            Text(initials)
                                .foregroundStyle(Theme.packageBrown)
                                .font(.title3.weight(.bold))
                        }

                        VStack(alignment: .leading) {
                            Text(viewModel.userDisplayName)
                                .font(.headline)
                                .fontWeight(.semibold)

                            Text(viewModel.userEmail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if let company = viewModel.currentCompany {
                        HStack {
                            Text("Company")
                            
                            Spacer()
                            
                            Text(company.name)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // No Company State
                if viewModel.currentCompany == nil {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("No Company Membership")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            
                            Text("You're currently logged in without a company. To access runs and other features, you'll need to join or create a company.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Button("Join Company") {
                                showJoinCompany = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Detailed User Information Section
                Section {
                    ProfileInfoSection(title: "User Information") {
                        ProfileInfoRow(label: "Name", value: viewModel.userDisplayName)
                        ProfileInfoRow(label: "Email", value: viewModel.userEmail)
                        if let role = viewModel.currentCompany?.role, !role.isEmpty {
                            ProfileInfoRow(label: "Role", value: viewModel.userRole.displayName)
                        }
                    }
                }

                // Navigation preference section
                Section {
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
                            Text("Directions App")
                            Spacer()
                            Text(preferredDirectionsApp.displayName)
                        }
                    }
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Choose which app launches when opening addresses from a run.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                // Authentication Details (only if we have credentials)
                if let credentials = viewModel.authService.loadStoredCredentials() {
                    Section {
                        ProfileInfoSection(title: "Authentication") {
                            ProfileInfoRow(label: "User ID", value: credentials.userID)
                            ProfileInfoRow(label: "Access Token", value: credentials.accessToken, monospaced: true)
                            ProfileInfoRow(label: "Expires", value: credentials.expiresAt.formatted(.dateTime.month().day().year().hour().minute()))
                        }
                    }
                }
                
                // Company Actions Section
                if viewModel.currentCompany != nil {
                    Section("Company Actions") {
                        if viewModel.canGenerateInvites {
                            Button(action: {
                                showInviteGenerator = true
                            }) {
                                HStack {
                                    Image(systemName: "qrcode")
                                        .foregroundColor(.blue)
                                    Text("Generate Invite Code")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            .buttonStyle(.plain)
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
                Section("Settings") {
                    if viewModel.currentCompany != nil {
                        Button(action: {
                            Task {
                                let success = await viewModel.leaveCompany()
                                if success {
                                    await authViewModel.refreshSessionFromStoredCredentials()
                                }
                            }
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
                        companyName: company.name
                    )
                }
            }
            .sheet(isPresented: $showJoinCompany) {
                JoinCompanyView {
                    Task {
                        await authViewModel.refreshSessionFromStoredCredentials()
                        viewModel.loadUserInfo()
                    }
                }
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

private struct ProfileInfoSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(spacing: 10) {
                content
            }
        }
    }
}

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
