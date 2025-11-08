//
//  ProfileView.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel(authService: AuthService())
    @State private var showInviteGenerator = false
    @State private var showJoinCompany = false
    
    var body: some View {
        NavigationView {
            List {
                // User Info Section
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.userDisplayName)
                                .font(.headline)
                            Text(viewModel.userEmail)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                // Company Info Section
                if let company = viewModel.currentCompany {
                    Section("Company") {
                        HStack {
                            Image(systemName: "building.2.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text(company.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Role: \(viewModel.userRole.displayName)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                    }
                }
                
                // Actions Section
                Section("Actions") {
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
                    }
                    
                    Button(action: {
                        showJoinCompany = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.green)
                            Text("Join Company")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // Settings Section
                Section("Settings") {
                    Button(action: {
                        viewModel.logout()
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
                JoinCompanyView()
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

#Preview {
    ProfileView()
}