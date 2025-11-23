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
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var isShowingSignup = false
    @FocusState private var focusedField: Field?
    @State private var notifications: [InAppNotification] = []

    private enum Field {
        case email
        case password
        case firstName
        case lastName
        case phone
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollView {
                        scrollableContent
                            .padding(.bottom, 20)
                    }
                    
                    Spacer()
                    
                    // Fixed bottom buttons
                    bottomButtons
                        .background(Color(.systemBackground))
                }
            }
            .navigationTitle(isShowingSignup ? "Create Account" : "Login")
            .navigationBarTitleDisplayMode(.large)
        }
        .onSubmit {
            switch focusedField {
            case .firstName:
                focusedField = .lastName
            case .lastName:
                focusedField = isShowingSignup ? .phone : .email
            case .phone:
                focusedField = .email
            case .email:
                focusedField = .password
            case .password, nil:
                if isShowingSignup {
                    createAccount()
                } else {
                    submitLogin()
                }
            }
        }
        .onAppear {
            refreshNotifications()
        }
        .onChange(of: authViewModel.phase) { _ in
            refreshNotifications()
        }
        .onChange(of: authViewModel.errorMessage) { _ in
            refreshNotifications()
        }
        .inAppNotifications(notifications) { notification in
            notifications.removeAll(where: { $0.id == notification.id })
            if authViewModel.errorMessage == notification.message {
                authViewModel.errorMessage = nil
            }
        }
    }

    private var scrollableContent: some View {
        VStack(spacing: 24) {
            // Input fields
            VStack(spacing: 16) {
                if isShowingSignup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("First Name")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        TextField("Enter your first name", text: $firstName)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .firstName)
                            .submitLabel(.next)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Name")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        TextField("Enter your last name", text: $lastName)
                            .textContentType(.familyName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .lastName)
                            .submitLabel(.next)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Phone (Optional)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        TextField("Enter your phone number", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .focused($focusedField, equals: .phone)
                            .submitLabel(.next)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

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
                        .submitLabel(isShowingSignup ? .next : .go)
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
            .padding(.top, 40)
        }
    }

    private var bottomButtons: some View {
        // Bottom buttons area
        VStack(spacing: 12) {
            if isShowingSignup {
                Button(action: createAccount) {
                    HStack(spacing: 12) {
                        if authViewModel.isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Theme.contrastOnBlackOnWhite)
                        }

                        Text(authViewModel.isProcessing ? "Creating…" : "Create Account")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Theme.contrastOnBlackOnWhite)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.blackOnWhite)
                    )
                }
                .disabled(authViewModel.isProcessing || email.isEmpty || password.isEmpty || firstName.isEmpty || lastName.isEmpty)
                
                Button("← Back to Login") {
                    focusedField = nil
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isShowingSignup = false
                        clearSignupFields()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.blackOnWhite)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button("Create Account") {
                    focusedField = nil
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isShowingSignup = true
                    }
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray4))
                )
                .disabled(authViewModel.isProcessing)
                
                Button(action: submitLogin) {
                    HStack(spacing: 12) {
                        if authViewModel.isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Theme.contrastOnBlackOnWhite)
                        }

                        Text(authViewModel.isProcessing ? "Signing In…" : "Log In")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Theme.contrastOnBlackOnWhite)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.blackOnWhite)
                    )
                }
                .disabled(authViewModel.isProcessing || email.isEmpty || password.isEmpty)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

extension LoginView {
    private func submitLogin() {
        guard !authViewModel.isProcessing,
              !email.isEmpty,
              !password.isEmpty else {
            return
        }

        focusedField = nil
        
        Task {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            email = trimmedEmail
            await authViewModel.login(email: trimmedEmail, password: password)
        }
    }

    private func createAccount() {
        guard !authViewModel.isProcessing,
              !email.isEmpty,
              !password.isEmpty,
              !firstName.isEmpty,
              !lastName.isEmpty else {
            return
        }

        focusedField = nil
        
        Task {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            email = trimmedEmail
            await authViewModel.createAccount(
                email: trimmedEmail,
                password: password,
                firstName: firstName,
                lastName: lastName,
                phone: phone.isEmpty ? nil : phone
            )
        }
    }

    private func clearSignupFields() {
        firstName = ""
        lastName = ""
        phone = ""
    }

    private func refreshNotifications() {
        var items: [InAppNotification] = []

        if case let .login(message) = authViewModel.phase, let message {
            items.append(
                InAppNotification(
                    message: message,
                    style: .info,
                    isDismissable: true
                )
            )
        }

        if let errorMessage = authViewModel.errorMessage {
            items.append(
                InAppNotification(
                    message: errorMessage,
                    style: .error
                )
            )
        }

        notifications = items
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
