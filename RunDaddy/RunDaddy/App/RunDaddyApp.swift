//
//  RunDaddyApp.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI

@main
struct RunDaddyApp: App {
    @StateObject private var sessionController = PackingSessionController()
    @State private var isLoggedIn = AuthService.shared.isLoggedIn()

    var body: some Scene {
        WindowGroup {
            if isLoggedIn {
                RootTabView()
                    .environmentObject(sessionController)
                    .environment(\.haptics, HapticFeedbackService.live)
            } else {
                LoginView {
                    isLoggedIn = true
                }
            }
        }
    }
}
