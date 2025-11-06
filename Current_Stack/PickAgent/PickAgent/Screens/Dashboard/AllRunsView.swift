//
//  AllRunsView.swift
//  PickAgent
//
//  Created by ChatGPT on 11/6/2025.
//

import SwiftUI
import Combine

struct AllRunsView: View {
    let session: AuthSession
    @StateObject private var viewModel: AllRunsViewModel
    @State private var showingDeleteAlert = false
    @State private var runToDelete: RunSummary?
    @State private var deletingRunIds: Set<String> = []
    
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
                                .disabled(deletingRunIds.contains(run.id))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        runToDelete = run
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
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
            .alert("Delete Run", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    runToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let run = runToDelete {
                        Task {
                            await deleteRun(run)
                        }
                    }
                }
            } message: {
                if let run = runToDelete {
                    let locationText = run.locationCount == 1 ? "location" : "locations"
                    Text("Are you sure you want to delete run with \(run.locationCount) \(locationText)? This action cannot be undone.")
                } else {
                    Text("Are you sure you want to delete this run? This action cannot be undone.")
                }
            }
        }
    }
    
    private func deleteRun(_ run: RunSummary) async {
        deletingRunIds.insert(run.id)
        
        do {
            try await viewModel.service.deleteRun(runId: run.id, credentials: session.credentials)
            await MainActor.run {
                // Remove the run from local state immediately for better UX
                viewModel.removeRun(run.id)
                runToDelete = nil
            }
        } catch {
            await MainActor.run {
                // Handle error - could show an alert
                print("Failed to delete run: \(error)")
                runToDelete = nil
            }
        }
        
        _ = await MainActor.run {
            deletingRunIds.remove(run.id)
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
    let service: RunsServicing

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
            // Fetch all runs from new endpoint
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
    
    func removeRun(_ runId: String) {
        runsByDate = runsByDate.map { dateSection in
            let filteredRuns = dateSection.runs.filter { $0.id != runId }
            return RunDateSection(date: dateSection.date, runs: filteredRuns)
        }.filter { !$0.runs.isEmpty }
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