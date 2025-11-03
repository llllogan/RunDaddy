//
//  RunHistoryView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI

private struct RunSection: Identifiable {
    let date: Date
    let runs: [APIRun]

    var id: Date { date }
}

struct RunHistoryView: View {
    @Environment(\.haptics) private var haptics
    @AppStorage("settings.webhookURL") private var webhookURL: String = ""
    @AppStorage("settings.apiKey") private var apiKey: String = ""
    @AppStorage("settings.email") private var userEmail: String = ""
    @StateObject private var mailIntegrationViewModel = MailIntegrationViewModel()

    @State private var runs: [APIRun] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var runPendingDeletion: APIRun?
    @State private var isConfirmingDeletion = false
    @State private var isMailSheetPresented = false

    private let runsService = RunsService()

    private var runSections: [RunSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: runs) { calendar.startOfDay(for: $0.createdAt) }
        let sortedDates = grouped.keys.sorted(by: >)
        return sortedDates.map { date in
            let entries = (grouped[date] ?? []).sorted { $0.createdAt > $1.createdAt }
            return RunSection(date: date, runs: entries)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView("Loading runs...")
                        .listRowBackground(Color.clear)
                } else if let error = errorMessage {
                    ContentUnavailableView("Error loading runs",
                                             systemImage: "exclamationmark.triangle",
                                             description: Text(error))
                        .listRowBackground(Color.clear)
                } else if runSections.isEmpty {
                    ContentUnavailableView("No runs yet",
                                             systemImage: "tray",
                                             description: Text("Import a CSV to start tracking runs."))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(runSections) { section in
                        Section(section.date.formatted(.dateTime.month().day().year())) {
                             ForEach(section.runs) { run in
                                 VStack(alignment: .leading, spacing: 4) {
                                     Text(runTitle(for: run))
                                         .font(.headline)
                                     Text(runSubtitle(for: run))
                                         .font(.caption)
                                         .foregroundStyle(.secondary)
                                 }
                                 .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                     Button(role: .destructive) {
                                         runPendingDeletion = run
                                         isConfirmingDeletion = true
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
            .refreshable {
                await fetchRuns()
            }
            .alert("Are you sure?", isPresented: $isConfirmingDeletion) {
                Button("Delete", role: .destructive) {
                    haptics.destructiveActionTap()
                    if let run = runPendingDeletion {
                        delete(run: run)
                    }
                    runPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    haptics.secondaryButtonTap()
                    runPendingDeletion = nil
                }
            } message: {
                if let run = runPendingDeletion {
                    Text("Are you sure you want to delete this run from \(run.createdAt.formatted(.dateTime.day().month().year()))?")
                }
            }
            .navigationTitle("Runs")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        haptics.secondaryButtonTap()
                        isMailSheetPresented = true
                    } label: {
                        Label("Compose Email", systemImage: "envelope.badge.plus")
                    }
                }
            }

            .sheet(isPresented: $isMailSheetPresented) {
                MailIntegrationSheet(viewModel: mailIntegrationViewModel,
                                      webhookURL: webhookURL,
                                      apiKey: apiKey,
                                      recipientEmail: userEmail)
            }
            .task {
                await fetchRuns()
            }
        }
    }



    private func fetchRuns() async {
        isLoading = true
        errorMessage = nil
        do {
            runs = try await runsService.fetchRuns()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(run: APIRun) {
        Task {
            do {
                try await runsService.deleteRun(id: run.id)
                runs.removeAll { $0.id == run.id }
            } catch {
                // TODO: Show error to user
                print("Failed to delete run: \(error)")
            }
        }
    }

    private func runTitle(for run: APIRun) -> String {
        let runnerName = run.runnerFullName ?? run.pickerFullName ?? "Unknown"
        return runnerName
    }

    private func runSubtitle(for run: APIRun) -> String {
        let status = run.status.capitalized
        let dateText = run.scheduledFor?.formatted(.dateTime.month().day()) ?? run.createdAt.formatted(.dateTime.month().day())
        return "\(status) - \(dateText)"
    }
}



#Preview {
    RunHistoryView()
//        .modelContainer(PreviewFixtures.container)
}
