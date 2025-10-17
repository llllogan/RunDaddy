//
//  SettingsView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI

private enum SettingsKeys {
    static let userName = "settings.username"
    static let userEmail = "settings.email"
    static let webhookURL = "settings.webhookURL"
    static let apiKey = "settings.apiKey"
}

struct SettingsView: View {
    @AppStorage(SettingsKeys.userName) private var userName: String = ""
    @AppStorage(SettingsKeys.userEmail) private var userEmail: String = ""
    @AppStorage(SettingsKeys.webhookURL) private var webhookURL: String = ""
    @AppStorage(SettingsKeys.apiKey) private var apiKey: String = ""

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
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
