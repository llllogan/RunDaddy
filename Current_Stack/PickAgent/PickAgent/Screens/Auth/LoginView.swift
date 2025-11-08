//
//  LoginView.swift
//  PickAgent
//
//  Created by ChatGPT on 3/15/2025.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top content area
                VStack(spacing: 24) {
                    // Status message
                    if case let .login(message) = authViewModel.phase, let message {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Error message
                    if let errorMessage = authViewModel.errorMessage {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Input fields
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            
                            TextField("Enter your email", text: $email)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            
                            SecureField("Enter your password", text: $password)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.top, 20)
                
                Spacer()
                
                // Bottom buttons area
                VStack(spacing: 12) {
                    Button(action: submitLogin) {
                        HStack(spacing: 12) {
                            if authViewModel.isProcessing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            }

                            Text(authViewModel.isProcessing ? "Creating…" : "Create Account")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray4))
                        )
                    }
                    .disabled(authViewModel.isProcessing || email.isEmpty || password.isEmpty)
                    
                    Button(action: submitLogin) {
                        HStack(spacing: 12) {
                            if authViewModel.isProcessing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            }

                            Text(authViewModel.isProcessing ? "Signing In…" : "Log In")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.packageBrown)
                        )
                    }
                    .disabled(authViewModel.isProcessing || email.isEmpty || password.isEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .navigationTitle("Login or Sign Up")
            .navigationBarTitleDisplayMode(.large)
        }
        .onSubmit(submitLogin)
    }

    private func submitLogin() {
        switch focusedField {
        case .email:
            focusedField = .password
        case .password, nil:
            guard !authViewModel.isProcessing,
                  !email.isEmpty,
                  !password.isEmpty else {
                return
            }

            Task {
                let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                email = trimmedEmail
                await authViewModel.login(email: trimmedEmail, password: password)
            }
        }
    }
}

#Preview {
    struct PreviewContent: View {
        @StateObject private var viewModel = AuthViewModel(service: PreviewAuthService())

        var body: some View {
            LoginView()
                .environmentObject(viewModel)
                .task {
                    await viewModel.bootstrap()
                }
        }
    }

    return PreviewContent()
}

