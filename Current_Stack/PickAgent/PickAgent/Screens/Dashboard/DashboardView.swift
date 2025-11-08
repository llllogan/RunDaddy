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
                if !viewModel.todayRuns.isEmpty || (viewModel.isLoading && viewModel.todayRuns.isEmpty) {
                    Section("Runs for Today") {
                        if viewModel.isLoading && viewModel.todayRuns.isEmpty {
                            LoadingStateRow()
                        } else {
                            ForEach(viewModel.todayRuns) { run in
                                NavigationLink {
                                    RunDetailView(runId: run.id, session: session)
                                } label: {
                                    RunRow(run: run)
                                }
                            }
                            Text("View 2 more")
                        }
                    }
                }

                // Only show "Runs to be Packed" section if there are runs or currently loading
                if !viewModel.runsToPack.isEmpty || (viewModel.isLoading && viewModel.runsToPack.isEmpty) {
                    Section("Runs to be Packed") {
                        if viewModel.isLoading && viewModel.runsToPack.isEmpty {
                            LoadingStateRow()
                        } else {
                            ForEach(viewModel.runsToPack) { run in
                                NavigationLink {
                                    RunDetailView(runId: run.id, session: session)
                                } label: {
                                    RunRow(run: run)
                                }
                            }
                            Text("View 5 more")
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

    }
}




