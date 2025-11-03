//
//  SettingsView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI

enum SettingsKeys {
    static let userName = "settings.username"
    static let userEmail = "settings.email"
    static let webhookURL = "settings.webhookURL"
    static let apiKey = "settings.apiKey"
    static let navigationApp = "settings.navigationApp"
    static let lastLoginDate = "settings.lastLoginDate"
    static let accessTokenExpiry = "settings.accessTokenExpiry"
    static let refreshTokenExpiry = "settings.refreshTokenExpiry"
    static let authUserId = "settings.authUserId"
    static let authCompanyId = "settings.authCompanyId"
    static let authContext = "settings.authContext"
}

enum NavigationApp: String, CaseIterable, Identifiable {
    case appleMaps
    case waze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMaps:
            return "Apple Maps"
        case .waze:
            return "Waze"
        }
    }

    var systemImageName: String {
        switch self {
        case .appleMaps:
            return "map"
        case .waze:
            return "car.fill"
        }
    }
}

struct SettingsView: View {
    @AppStorage(SettingsKeys.userName) private var userName: String = ""
    @AppStorage(SettingsKeys.userEmail) private var userEmail: String = ""
    @AppStorage(SettingsKeys.webhookURL) private var webhookURL: String = ""
    @AppStorage(SettingsKeys.apiKey) private var apiKey: String = ""
    @AppStorage(SettingsKeys.navigationApp) private var navigationAppRawValue: String = NavigationApp.appleMaps.rawValue
    @AppStorage(SettingsKeys.lastLoginDate) private var lastLoginDate: String = ""
    @AppStorage(SettingsKeys.accessTokenExpiry) private var accessTokenExpiry: String = ""
    @AppStorage(SettingsKeys.refreshTokenExpiry) private var refreshTokenExpiry: String = ""
    @AppStorage(SettingsKeys.authUserId) private var authUserId: String = ""
    @AppStorage(SettingsKeys.authCompanyId) private var authCompanyId: String = ""
    @AppStorage(SettingsKeys.authContext) private var authContext: String = ""

    private var navigationAppBinding: Binding<NavigationApp> {
        Binding<NavigationApp> {
            NavigationApp(rawValue: navigationAppRawValue) ?? .appleMaps
        } set: { newValue in
            navigationAppRawValue = newValue.rawValue
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Your name", text: $userName)
                        .textContentType(.name)
                        .autocapitalization(.words)
                    TextField("Email address", text: $userEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section("Integrations") {
                    TextField("Google Webhook URL", text: $webhookURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section("Navigation") {
                    Picker("Open directions in:", selection: navigationAppBinding) {
                        ForEach(NavigationApp.allCases) { app in
                            Text(app.title)
                                .tag(app)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Authentication Debug") {
                    Text("Last Login: \(lastLoginDate.isEmpty ? "Never" : lastLoginDate)")
                    Text("Access Token Expiry: \(accessTokenExpiry.isEmpty ? "N/A" : accessTokenExpiry)")
                    Text("Refresh Token Expiry: \(refreshTokenExpiry.isEmpty ? "N/A" : refreshTokenExpiry)")
                    Text("User ID: \(authUserId.isEmpty ? "N/A" : authUserId)")
                    Text("Company ID: \(authCompanyId.isEmpty ? "N/A" : authCompanyId)")
                    Text("Context: \(authContext.isEmpty ? "N/A" : authContext)")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
