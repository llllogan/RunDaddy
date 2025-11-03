//
//  APIRunDetailView.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import SwiftUI

struct APIRunDetailView: View {
    let run: APIRun

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Run Details")
                    .font(.title)
                    .bold()

                Group {
                    Text("ID: \(run.id)")
                    Text("Status: \(run.status)")
                    if let scheduled = run.scheduledFor {
                        Text("Scheduled: \(scheduled.formatted())")
                    }
                    if let started = run.pickingStartedAt {
                        Text("Started: \(started.formatted())")
                    }
                    if let ended = run.pickingEndedAt {
                        Text("Ended: \(ended.formatted())")
                    }
                    Text("Created: \(run.createdAt.formatted())")
                    if let pickerName = run.pickerFullName {
                        Text("Picker: \(pickerName)")
                    }
                    if let runnerName = run.runnerFullName {
                        Text("Runner: \(runnerName)")
                    }
                }
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("Run Detail")
    }
}