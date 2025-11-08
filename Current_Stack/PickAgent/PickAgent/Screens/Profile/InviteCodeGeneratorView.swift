//
//  InviteCodeGeneratorView.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import SwiftUI

struct InviteCodeGeneratorView: View {
    @StateObject private var viewModel = InviteCodeGeneratorViewModel()
    @Environment(\.dismiss) private var dismiss
    
    let companyId: String
    let companyName: String
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
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
                            
                            VStack(spacing: 8) {
                                Text("Invite Code")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Text(inviteCode.code)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            
                            VStack(spacing: 4) {
                                Text("Role: \(inviteCode.roleDisplay)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("Expires: \(inviteCode.expiresAtDisplay)")
                                    .font(.caption)
                                    .foregroundColor(inviteCode.isExpired ? .red : .gray)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(16)
                        
                        // Action Buttons
                        VStack(spacing: 12) {
                            Button("Generate New Code") {
                                viewModel.generateInviteCode(companyId: companyId)
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Done") {
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                        }
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
                            VStack(alignment: .leading, spacing: 8) {
                                Text("User Role")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                
                                ForEach(UserRole.allCases, id: \.self) { role in
                                    Button(action: {
                                        viewModel.selectedRole = role
                                    }) {
                                        HStack {
                                            Text(role.displayName)
                                            Spacer()
                                            if viewModel.selectedRole == role {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.blue)
                                            } else {
                                                Image(systemName: "circle")
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        .padding()
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            
                            // Generate Button
                            Button(action: {
                                viewModel.generateInviteCode(companyId: companyId)
                            }) {
                                HStack {
                                    if viewModel.isGenerating {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                    Text(viewModel.isGenerating ? "Generating..." : "Generate Invite Code")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(viewModel.selectedRole == nil ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(viewModel.selectedRole == nil || viewModel.isGenerating)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Invite User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
        }
    }
}

#Preview {
    InviteCodeGeneratorView(
        companyId: "company-123",
        companyName: "Test Company"
    )
}