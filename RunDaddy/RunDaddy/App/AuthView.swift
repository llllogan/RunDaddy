//
//  AuthView.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import SwiftUI

struct AuthView: View {
    @State private var isLoggedIn = false
    private let authService = AuthService()

    var body: some View {
        Group {
            if isLoggedIn {
                RootTabView()
            } else {
                LoginView(onLoginSuccess: {
                    isLoggedIn = true
                })
            }
        }
        .onAppear {
            checkAuth()
        }
    }

    private func checkAuth() {
        isLoggedIn = authService.getStoredAuth() != nil
    }
}