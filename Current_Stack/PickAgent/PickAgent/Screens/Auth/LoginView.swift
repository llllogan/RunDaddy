//
//  LoginView.swift
//  PickAgent
//
//  Created by ChatGPT on 3/15/2025.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?
    @State private var glowPulse = false

    private enum Field {
        case username
        case password
    }

    var body: some View {
        ZStack {
            GlassBackground(glowPulse: $glowPulse)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Text("RunDaddy")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)

                    Text("PickAgent Portal")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.top, 12)

                glassCard

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
        }
        .task {
            guard !glowPulse else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .onSubmit(submitLogin)
    }

    private var glassCard: some View {
        VStack(spacing: 20) {
            if case let .login(message) = authViewModel.phase, let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)
            }

            if let errorMessage = authViewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
            }

            frostedField(
                title: "Username",
                systemImage: "person.fill",
                text: $username,
                field: .username,
                isSecure: false
            )

            frostedField(
                title: "Password",
                systemImage: "lock.fill",
                text: $password,
                field: .password,
                isSecure: true
            )

            Button(action: submitLogin) {
                HStack {
                    if authViewModel.isProcessing {
                        ProgressView()
                            .tint(.white)
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .imageScale(.large)
                    }

                    Text(authViewModel.isProcessing ? "Signing In..." : "Enter Dashboard")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.packageBrown)
            .controlSize(.large)
            .disabled(authViewModel.isProcessing || username.isEmpty || password.isEmpty)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.25), radius: 25, y: 15)
        )
        .animation(.easeInOut(duration: 0.2), value: authViewModel.isProcessing)
    }

    private func frostedField(
        title: String,
        systemImage: String,
        text: Binding<String>,
        field: Field,
        isSecure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .foregroundStyle(.white.opacity(0.85))

                if isSecure {
                    SecureField("Enter \(title.lowercased())", text: text)
                        .textContentType(.password)
                        .focused($focusedField, equals: field)
                        .submitLabel(field == .password ? .go : .next)
                } else {
                    TextField("Enter \(title.lowercased())", text: text)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: field)
                        .submitLabel(.next)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func submitLogin() {
        switch focusedField {
        case .username:
            focusedField = .password
        case .password, nil:
            guard !authViewModel.isProcessing,
                  !username.isEmpty,
                  !password.isEmpty else {
                return
            }

            Task {
                let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
                username = trimmedUsername
                await authViewModel.login(username: trimmedUsername, password: password)
            }
        }
    }
}

private struct GlassBackground: View {
    @Binding var glowPulse: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 22 / 255, green: 18 / 255, blue: 33 / 255),
                        Color(red: 35 / 255, green: 28 / 255, blue: 56 / 255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color(red: 81 / 255, green: 133 / 255, blue: 227 / 255).opacity(0.45))
                    .frame(width: size.width * 0.9)
                    .blur(radius: glowPulse ? 70 : 40)
                    .offset(x: -size.width * 0.32, y: -size.height * 0.4)
                    .blendMode(.screen)

                Circle()
                    .fill(Color(red: 245 / 255, green: 199 / 255, blue: 104 / 255).opacity(0.55))
                    .frame(width: size.width * 0.75)
                    .blur(radius: glowPulse ? 85 : 45)
                    .offset(x: size.width * 0.35, y: -size.height * 0.3)
                    .blendMode(.screen)

                Circle()
                    .fill(Theme.packageBrown.opacity(0.75))
                    .frame(width: size.width * 0.8)
                    .blur(radius: glowPulse ? 60 : 30)
                    .offset(x: 0, y: size.height * 0.4)
                    .blendMode(.screen)

                AngularGradient(
                    gradient: Gradient(colors: [
                        .white.opacity(0.18),
                        .clear,
                        .white.opacity(0.12),
                        .clear
                    ]),
                    center: .center,
                    angle: .degrees(glowPulse ? 360 : 0)
                )
                .scaleEffect(1.2)
                .opacity(0.9)
                .blendMode(.screen)
            }
        }
        .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: glowPulse)
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

private final class PreviewAuthService: AuthServicing {
    func loadStoredCredentials() -> AuthCredentials? { nil }
    func store(credentials: AuthCredentials) {}
    func clearStoredCredentials() {}
    func refresh(using credentials: AuthCredentials) async throws -> AuthCredentials { credentials }
    func login(username: String, password: String) async throws -> AuthCredentials {
        AuthCredentials(
            accessToken: "demo",
            refreshToken: "demo",
            userID: "preview",
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
}
