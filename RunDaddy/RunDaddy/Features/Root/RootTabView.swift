//
//  RootTabView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    var body: some View {
        TabView {
            RunHistoryView()
                .tabItem {
                    Label("Runs", systemImage: "figure.run")
                }

            MachinesView()
                .tabItem {
                    Label("Machines", systemImage: "building")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.xaxis")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewFixtures.container)
}
