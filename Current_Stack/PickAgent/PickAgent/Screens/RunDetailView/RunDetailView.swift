//
//  RunDetailView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/25/2025.
//

import SwiftUI

struct RunDetailView: View {
    let runId: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RunOverviewBento(run: run,
                                     locationSections: locationSections,
                                     machineCount: machineCount,
                                     totalCoils: totalCoils,
                                     packedCount: packedCount,
                                     notPackedCount: notPackedCount)
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    Text("Run Overview")
                }
            }
        }
        .navigationTitle("Run Details")
    }
}

#Preview {
    NavigationStack {
        RunDetailView(runId: "run-12345")
    }
}
