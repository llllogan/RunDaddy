//
//  Dashboard.swift
//  PickAgent
//
//  Created by Logan Janssen on 4/11/2025.
//

import SwiftUI
import Charts

struct DashboardView: View {
    let session: AuthSession
    let logoutAction: () -> Void

    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var chartsViewModel: ChartsViewModel
    @State private var isShowingProfile = false
    @State private var chartRefreshTrigger = false

    private var hasCompany: Bool {
        // User has company if they have company memberships
        viewModel.currentUserProfile?.hasCompany ?? false
    }

    private var navigationSubtitleText: String {
        let companyName = viewModel.currentUserProfile?.currentCompany?.name ?? "No Company"
        let dateString = Date().formatted(
            .dateTime
                .weekday(.wide)
                .month(.abbreviated)
                .day()
        )
        return "\(companyName), \(dateString)"
    }

    init(session: AuthSession, logoutAction: @escaping () -> Void) {
        self.session = session
        self.logoutAction = logoutAction
        _viewModel = StateObject(wrappedValue: DashboardViewModel(session: session))
        _chartsViewModel = StateObject(wrappedValue: ChartsViewModel(session: session))
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
                                    RunRow(run: run, currentUserId: session.credentials.userID)
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
                                    RunRow(run: run, currentUserId: session.credentials.userID)
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
                    DailyInsightsChartView(viewModel: chartsViewModel, refreshTrigger: chartRefreshTrigger)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    
                    NavigationLink {
                        AnalyticsView(session: session)
                    } label: {
                        Text("View more data")
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Hi \(session.profile.firstName)")
            .navigationSubtitle(navigationSubtitleText)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
            chartRefreshTrigger.toggle()
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
            chartsViewModel.updateSession(newSession)
            Task {
                await viewModel.loadRuns(force: true)
            }
        }

    }
}
