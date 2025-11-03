//
//  ContentView.swift
//  PickAgent
//
//  Created by Logan Janssen on 3/11/2025.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        Group {
            switch authViewModel.phase {
            case .loading:
                LoadingStateView()
            case let .authenticated(credentials):
                DashboardView(userID: credentials.userID) {
                    authViewModel.logout()
                }
            case .login:
                LoginView()
            }
        }
        .task {
            if case .loading = authViewModel.phase {
                await authViewModel.bootstrap()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authViewModel.phase)
    }
}

private struct DashboardView: View {
    let userID: String
    let logoutAction: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Runs for Today") {
                    EmptyStateRow(message: "You're all set. No runs scheduled for today.")
                }

                Section("Runs to be Packed") {
                    EmptyStateRow(message: "Nothing to pack right now. New runs will appear here.")
                }

                Section("Insights") {
                    EmptyStateRow(message: "Insights will show up once you start running orders.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Hello \(userID)")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(role: .destructive, action: logoutAction) {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Label("Profile", systemImage: "person.fill")
                            .tint(Theme.packageBrown)
                    }
                }
            }
        }
        .tint(Theme.packageBrown)
    }
}

private struct LoadingStateView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(Theme.packageBrown)

                Text("Loading your session…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

private struct EmptyStateRow: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

#Preview {
    RootView()
        .environmentObject(AuthViewModel(service: PreviewAuthService()))
}

private final class PreviewAuthService: AuthServicing {
    func loadStoredCredentials() -> AuthCredentials? {
        AuthCredentials(
            accessToken: "token",
            refreshToken: "refresh",
            userID: "Logan",
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    func store(credentials: AuthCredentials) {}
    func clearStoredCredentials() {}

    func refresh(using credentials: AuthCredentials) async throws -> AuthCredentials {
        credentials
    }

    func login(username: String, password: String) async throws -> AuthCredentials {
        credentials
    }

    private var credentials: AuthCredentials {
        AuthCredentials(
            accessToken: "token",
            refreshToken: "refresh",
            userID: "Logan",
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
}
