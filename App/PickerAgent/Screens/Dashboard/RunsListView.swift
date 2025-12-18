//
//  RunsListView.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import SwiftUI

struct RunsListView: View {
    let session: AuthSession
    let title: String
    let runs: [RunSummary]
    var emptyStateMessage = "No runs to show."

    private var showPackedByYouChip: Bool {
        !runs.contains { $0.runner?.id == session.credentials.userID }
    }

    private var sortedRuns: [RunSummary] {
        runs.sorted { lhs, rhs in
            let lhsDate = lhs.scheduledFor ?? lhs.createdAt
            let rhsDate = rhs.scheduledFor ?? rhs.createdAt
            return lhsDate > rhsDate
        }
    }

    var body: some View {
        List {
            if runs.isEmpty {
                Section {
                    EmptyStateRow(message: emptyStateMessage)
                }
            } else {
                Section {
                    ForEach(sortedRuns) { run in
                        NavigationLink {
                            RunDetailView(runId: run.id, session: session)
                        } label: {
                            RunRow(
                                run: run,
                                currentUserId: session.credentials.userID,
                                showPackedByYouChip: showPackedByYouChip
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let credentials = AuthCredentials(
        accessToken: "preview-token",
        refreshToken: "preview-refresh",
        userID: "user-1",
        expiresAt: Date().addingTimeInterval(3600)
    )
    let profile = UserProfile(
        id: "user-1",
        email: "jordan@example.com",
        firstName: "Jordan",
        lastName: "Smith",
        phone: nil,
        role: "PICKER"
    )
    let session = AuthSession(credentials: credentials, profile: profile)

    let runs = (0..<5).map { index in
        RunSummary(
            id: "run-\(index)",
            status: "READY",
            scheduledFor: Calendar.current.date(byAdding: .hour, value: index, to: Date()),
            pickingStartedAt: nil,
            pickingEndedAt: nil,
            createdAt: Date(),
            locationCount: 3,
            chocolateBoxes: [],
            runner: nil,
            hasPackingSessionForCurrentUser: false
        )
    }

    NavigationStack {
        RunsListView(session: session, title: "Runs for Today", runs: runs)
    }
}
