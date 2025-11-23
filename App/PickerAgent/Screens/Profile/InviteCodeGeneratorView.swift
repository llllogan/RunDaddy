//
//  InviteCodeGeneratorView.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import SwiftUI

struct InviteCodeGeneratorView: View {
    @StateObject private var viewModel = InviteCodeGeneratorViewModel(
        inviteCodesService: InviteCodesService(),
        authService: AuthService()
    )
    @Environment(\.dismiss) private var dismiss
    
    let companyId: String
    let companyName: String
    let roleCapacities: [InviteRoleCapacity]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if let inviteCode = viewModel.generatedInviteCode {
                        // QR Code Display
                        VStack(spacing: 16) {
                            Text("Share this QR Code")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            QRCodeView(code: inviteCode.code, size: 250)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(radius: 4)
                            
                            VStack(spacing: 4) {
                                Text("Role: \(inviteCode.roleDisplay)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("Expires: \(inviteCode.expiresAtDisplay)")
                                    .font(.caption)
                                    .foregroundColor(inviteCode.isExpired ? .red : .gray)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(16)
                    } else {
                        // Generate Code Form
                            VStack(spacing: 20) {
                                Text("Generate Invite Code")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                Text("Create an invite code for \(companyName)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                
                                // Role Selection
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("User Role")
                                        .font(.headline)
                                        .fontWeight(.medium)
                                    
                                ForEach(roleCapacities) { capacity in
                                    let isSelected = viewModel.selectedRole == capacity.role
                                    let isExhausted = capacity.remaining <= 0

                                    Button(action: {
                                        guard !isExhausted else { return }
                                        viewModel.selectedRole = capacity.role
                                    }) {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(capacity.role.displayName)
                                                    .foregroundStyle(isExhausted ? Color.gray : Color.primary)
                                                Text("\(capacity.remaining) remaining (\(capacity.used)/\(capacity.max) used)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(isSelected ? .blue : .gray)
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(10)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .disabled(isExhausted || viewModel.isGenerating)
                                }
                                }
                            
                            if allCapacitiesExhausted {
                                Text("Your current plan is at capacity for new members.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                .padding(.top, 16)
            }
            .navigationTitle("Invite User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.generatedInviteCode != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Regenerate", systemImage: "repeat") {
                            viewModel.generateInviteCode(companyId: companyId)
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
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
        .onAppear {
            // Check if user has permission to generate codes
            viewModel.checkPermissions(companyId: companyId)
            if viewModel.selectedRole == nil {
                viewModel.selectedRole = roleCapacities.first(where: { $0.remaining > 0 })?.role
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: {
                    viewModel.generateInviteCode(companyId: companyId)
                }) {
                    HStack {
                        if viewModel.isGenerating {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(viewModel.isGenerating ? "Generating..." : "Generate Invite Code")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(generateDisabled ? Color.gray.opacity(0.6) : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(generateDisabled)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var generateDisabled: Bool {
        guard let selected = viewModel.selectedRole else { return true }
        guard let capacity = roleCapacities.first(where: { $0.role == selected }) else { return true }
        return viewModel.isGenerating || capacity.remaining <= 0
    }

    private var allCapacitiesExhausted: Bool {
        roleCapacities.allSatisfy { $0.remaining <= 0 }
    }
}

#Preview {
    InviteCodeGeneratorView(
        companyId: "company-123",
        companyName: "Test Company",
        roleCapacities: [
            InviteRoleCapacity(role: .owner, used: 1, max: 1),
            InviteRoleCapacity(role: .admin, used: 0, max: 1),
            InviteRoleCapacity(role: .picker, used: 2, max: 3)
        ]
    )
}
