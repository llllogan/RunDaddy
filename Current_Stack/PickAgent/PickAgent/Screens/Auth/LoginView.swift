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
            Form {

                if case let .login(message) = authViewModel.phase, let message {
                    Section("Status") {
                        Text(message)
                            .font(.subheadline)
                    }
                }

                if let errorMessage = authViewModel.errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(Color.red)
                    }
                }

                Section("Credentials") {
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                    
                    Button(action: submitLogin) {
                        HStack(spacing: 12) {
                            if authViewModel.isProcessing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }

                            Text(authViewModel.isProcessing ? "Signing In…" : "Log In")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.packageBrown)
                    .disabled(authViewModel.isProcessing || email.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("Login")
            .formStyle(.grouped)
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

