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
            case let .authenticated(session):
                DashboardView(session: session) {
                    authViewModel.logout()
                }
            case .login:
                LoginView()
            case let .updateRequired(requiredVersion):
                UpdateRequiredView(requiredVersion: requiredVersion)
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

private struct LoadingStateView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()

                Text("Just a second…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
