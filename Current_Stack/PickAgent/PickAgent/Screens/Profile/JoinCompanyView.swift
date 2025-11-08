//
//  JoinCompanyView.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import SwiftUI

struct JoinCompanyView: View {
    @StateObject private var viewModel = JoinCompanyViewModel(
        inviteCodesService: InviteCodesService(),
        authService: AuthService()
    )
    @Environment(\.dismiss) private var dismiss
    @State private var showScanner = false
    @State private var hasNotifiedJoinSuccess = false
    
    var onCompanyJoined: (() -> Void)? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if let membership = viewModel.joinedMembership {
                    // Success View
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("Successfully Joined!")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("You are now a member of \(membership.company?.name ?? "the company")")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Role:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(membership.roleDisplay)
                            }
                            
                            HStack {
                                Text("Company:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(membership.company?.name ?? "Unknown")
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding()
                } else {
                    // Main Join Flow
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 50))
                                .foregroundColor(.blue)
                            
                            Text("Join Company")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Scan a QR code from an admin or owner to join their company")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        
                        // QR Scanner Button
                        Button(action: {
                            showScanner = true
                        }) {
                            HStack {
                                Image(systemName: "camera")
                                Text("Scan QR Code")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(viewModel.isJoining)
                    }
                    .padding()
                    
                    // Loading Overlay
                    if viewModel.isJoining {
                        Color.black.opacity(0.3)
                            .overlay(
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("Joining company...")
                                        .foregroundColor(.white)
                                }
                            )
                    }
                }
            }
            .navigationTitle("Join Company")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.joinedMembership == nil {
                        Button("Cancel") {
                            dismiss()
                        }
                    } else {
                        Button("Continue") {
                            notifyJoinSuccessIfNeeded()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
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
            .sheet(isPresented: $showScanner) {
                QRScannerView(
                    onCodeFound: { code in
                        showScanner = false
                        viewModel.joinWithQRCode(code)
                    },
                    onCancel: {
                        showScanner = false
                    }
                )
            }
            .onChange(of: viewModel.joinedMembership) { membership in
                if membership != nil {
                    notifyJoinSuccessIfNeeded()
                }
            }
        }
    }

    private func notifyJoinSuccessIfNeeded() {
        guard !hasNotifiedJoinSuccess else { return }
        hasNotifiedJoinSuccess = true
        onCompanyJoined?()
    }
}

#Preview {
    JoinCompanyView()
}
