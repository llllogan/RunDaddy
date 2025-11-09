//
//  Dashboard.swift
//  PickAgent
//
//  Created by Logan Janssen on 4/11/2025.
//

import SwiftUI

struct DashboardView: View {
    let session: AuthSession
    let logoutAction: () -> Void

    @StateObject private var viewModel: DashboardViewModel
    @State private var isShowingProfile = false

    private var hasCompany: Bool {
        // User has company if they have company memberships
        viewModel.currentUserProfile?.hasCompany ?? false
    }

    init(session: AuthSession, logoutAction: @escaping () -> Void) {
        self.session = session
        self.logoutAction = logoutAction
        _viewModel = StateObject(wrappedValue: DashboardViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            List {
                if let message = viewModel.errorMessage {
                    Section {
                        ErrorStateRow(message: message)
                    }
                }

                // Only show "Runs for Today" section if there are runs or currently loading
                if !viewModel.todayRuns.isEmpty
                    || (viewModel.isLoading && viewModel.todayRuns.isEmpty)
                {
                    Section("Runs for Today") {
                        if viewModel.isLoading && viewModel.todayRuns.isEmpty {
                            LoadingStateRow()
                        } else {
                            ForEach(viewModel.todayRuns.prefix(3)) { run in
                                NavigationLink {
                                    RunDetailView(runId: run.id, session: session)
                                } label: {
                                    RunRow(run: run)
                                }
                            }
                            if viewModel.todayRuns.count > 3 {
                                NavigationLink {
                                    RunsListView(
                                        session: session,
                                        title: "Runs for Today",
                                        runs: viewModel.todayRuns
                                    )
                                } label: {
                                    ViewMoreRow(title: "View \(viewModel.todayRuns.count - 3) more")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Only show "Runs to be Packed" section if there are runs or currently loading
                if !viewModel.tomorrowRuns.isEmpty || (viewModel.isLoading && viewModel.tomorrowRuns.isEmpty)
                {
                    Section("Runs for Tomorrow") {
                        if viewModel.isLoading && viewModel.tomorrowRuns.isEmpty {
                            LoadingStateRow()
                        } else {
                            ForEach(viewModel.tomorrowRuns.prefix(3)) { run in
                                NavigationLink {
                                    RunDetailView(runId: run.id, session: session)
                                } label: {
                                    RunRow(run: run)
                                }
                            }
                            if viewModel.tomorrowRuns.count > 3 {
                                NavigationLink {
                                    RunsListView(
                                        session: session,
                                        title: "Runs for Tomorrow",
                                        runs: viewModel.tomorrowRuns
                                    )
                                } label: {
                                    ViewMoreRow(title: "View \(viewModel.tomorrowRuns.count - 3) more")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("All Runs") {
                    NavigationLink {
                        AllRunsView(session: session)
                    } label: {
                        HStack {
                            Text("View All Runs")
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Insights") {
                    EmptyStateRow(message: "Insights will show up once you start running orders.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Hello \(session.profile.displayName)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            isShowingProfile = true
                        }
                    } label: {
                        Label("Profile", systemImage: "person.fill")
                    }
                }
            }
        }
        .task {
            await viewModel.loadRuns()
        }
        .refreshable {
            await viewModel.loadRuns(force: true)
        }
        .sheet(isPresented: $isShowingProfile) {
            ProfileView(
                isPresentedAsSheet: true,
                onDismiss: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        isShowingProfile = false
                    }
                },
                onLogout: logoutAction
            )
            .presentationDetents([.large])
            .presentationCornerRadius(28)
            .presentationDragIndicator(.visible)
            .presentationCompactAdaptation(.fullScreenCover)
        }
        .onChange(of: session, initial: false) { _, newSession in
            viewModel.updateSession(newSession)
            Task {
                await viewModel.loadRuns(force: true)
            }
        }

    }
}
