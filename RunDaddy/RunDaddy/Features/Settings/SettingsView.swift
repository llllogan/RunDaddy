//
//  SettingsView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Notifications", isOn: .constant(true))
                    Toggle("Use Cellular Data", isOn: .constant(false))
                }
                Section {
                    Button("Manage Permissions") {}
                    Button("About RunDaddy") {}
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
