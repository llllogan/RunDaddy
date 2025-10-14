//
//  SettingsView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI

private enum SettingsKeys {
    static let userName = "settings.username"
}

struct SettingsView: View {
    @AppStorage(SettingsKeys.userName) private var userName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Your name", text: $userName)
                        .textContentType(.name)
                        .autocapitalization(.words)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
