//
//  LoginView.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let authService = AuthService()

    var onLoginSuccess: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button(action: login) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Log In")
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isLoading)
                }
            }
            .navigationTitle("Log In")
        }
    }

    private func login() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let authContext = try await authService.login(email: email, password: password)
                authService.storeAuth(authContext)
                updateSettingsMetadata(authContext)
                onLoginSuccess()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func updateSettingsMetadata(_ auth: AuthContext) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        UserDefaults.standard.set(dateFormatter.string(from: Date()), forKey: SettingsKeys.lastLoginDate)
        UserDefaults.standard.set(dateFormatter.string(from: auth.accessTokenExpiresAt), forKey: SettingsKeys.accessTokenExpiry)
        UserDefaults.standard.set(dateFormatter.string(from: auth.refreshTokenExpiresAt), forKey: SettingsKeys.refreshTokenExpiry)
        UserDefaults.standard.set(auth.user.id, forKey: SettingsKeys.authUserId)
        UserDefaults.standard.set(auth.company.id, forKey: SettingsKeys.authCompanyId)
        UserDefaults.standard.set(auth.context, forKey: SettingsKeys.authContext)
    }
}