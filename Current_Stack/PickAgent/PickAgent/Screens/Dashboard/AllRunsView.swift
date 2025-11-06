//
//  AllRunsView.swift
//  PickAgent
//
//  Created by ChatGPT on 11/6/2025.
//

import SwiftUI
import Combine

// Reuse the same components from Dashboard
private struct RunRow: View {
    let run: RunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(run.locationCount) \(run.locationCount > 1 ? "Locations" : "Location")")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 0) {
                Text("Runner: ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(run.runner?.displayName ?? "No runner yet")")
                    .font(.subheadline)
            }
            .padding(.bottom, 4)
            
            HStack(spacing: 6) {
                PillChip(title: nil, date: nil, text: run.statusDisplay, colour: statusBackgroundColor, foregroundColour: statusForegroundColor)
                
                if let started = run.pickingStartedAt {
                    PillChip(title: "Started", date: started, text: nil, colour: nil, foregroundColour: nil)
                }
                if let ended = run.pickingEndedAt {
                    PillChip(title: "Ended", date: ended, text: nil, colour: nil, foregroundColour: nil)
                }
            }
        }
        .padding(.vertical, 0)
    }

    private var statusBackgroundColor: Color {
        switch run.status {
        case "READY":
            return Theme.packageBrown.opacity(0.12)
        case "PICKING":
            return .orange.opacity(0.15)
        case "PICKED":
            return .green.opacity(0.15)
        default:
            return Color(.systemGray5)
        }
    }

    private var statusForegroundColor: Color {
        switch run.status {
        case "READY":
            return Theme.packageBrown
        case "PICKING":
            return .orange
        case "PICKED":
            return .green
        default:
            return .secondary
        }
    }
}

private struct PillChip: View {
    let title: String?
    let date: Date?
    let text: String?
    let colour: Color?
    let foregroundColour: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let title = title {
                Text(title.uppercased())
                    .font(.caption2.bold())
            }
            
            if let text = text {
                Text(text)
                    .foregroundStyle(foregroundColour!)
                    .font(.caption2.bold())
                
            } else if let date = date {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(colour != nil ? Color(colour!) : Color(.systemGray6))
        .clipShape(Capsule())
    }
}

// Reuse the same components from Dashboard
private struct ErrorStateRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

private struct EmptyStateRow: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

private struct LoadingStateRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Theme.packageBrown)
            Text("Loading…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

struct AllRunsView: View {
    let session: AuthSession
    @StateObject private var viewModel: AllRunsViewModel
    
    init(session: AuthSession) {
        self.session = session
        _viewModel = StateObject(wrappedValue: AllRunsViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            List {
                if let message = viewModel.errorMessage {
                    Section {
                        ErrorStateRow(message: message)
                    }
                }

                if viewModel.isLoading && viewModel.runsByDate.isEmpty {
                    LoadingStateRow()
                } else if viewModel.runsByDate.isEmpty {
                    EmptyStateRow(message: "No runs found.")
                } else {
                    ForEach(viewModel.runsByDate, id: \.date) { dateSection in
                        Section(dateSection.headerText) {
                            ForEach(dateSection.runs) { run in
                                NavigationLink {
                                    RunDetailView(runId: run.id, session: session)
                                } label: {
                                    RunRow(run: run)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("All Runs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.loadRuns(force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await viewModel.loadRuns()
            }
            .refreshable {
                await viewModel.loadRuns(force: true)
            }
        }
    }
}

private struct RunDateSection: Identifiable {
    let id = UUID()
    let date: Date
    let runs: [RunSummary]
    
    var headerText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            return date.formatted(.dateTime.month().day().weekday(.wide))
        }
    }
}

@MainActor
fileprivate final class AllRunsViewModel: ObservableObject {
    @Published private(set) var runsByDate: [RunDateSection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let session: AuthSession
    private let service: RunsServicing

    convenience init(session: AuthSession) {
        self.init(session: session, service: RunsService())
    }

    init(session: AuthSession, service: RunsServicing) {
        self.session = session
        self.service = service
    }

    func loadRuns(force: Bool = false) async {
        if isLoading && !force {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Fetch all runs from the new endpoint
            let allRuns = try await service.fetchAllRuns(credentials: session.credentials)
            
            // Group runs by date
            let groupedRuns = Dictionary(grouping: allRuns) { run in
                let calendar = Calendar.current
                let date = run.scheduledFor ?? run.createdAt
                return calendar.startOfDay(for: date)
            }
            
            // Create date sections sorted by date (newest first)
            let sortedDates = groupedRuns.keys.sorted { $0 > $1 }
            runsByDate = sortedDates.map { date in
                RunDateSection(date: date, runs: groupedRuns[date] ?? [])
            }
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "We couldn't load your runs right now. Please try again."
            }
            runsByDate = []
        }

        isLoading = false
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

    return NavigationStack {
        AllRunsView(session: session)
    }
}
