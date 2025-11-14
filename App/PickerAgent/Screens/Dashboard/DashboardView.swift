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
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @State private var showingSearchResults = false
    private let searchService = SearchService()

    private var hasCompany: Bool {
        // User has company if they have company memberships
        viewModel.currentUserProfile?.hasCompany ?? false
    }

    private var isPickerUser: Bool {
        let roleValue = viewModel.currentUserProfile?.role ?? session.profile.role
        guard let role = roleValue?.uppercased(),
              let resolvedRole = UserRole(rawValue: role)
        else {
            return false
        }
        return resolvedRole == .picker
    }

    private var shouldShowInsights: Bool {
        hasCompany && !isPickerUser
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
                if showingSearchResults {
                    Section("Search Results") {
                        if searchResults.isEmpty {
                            Text("No results found")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(searchResults) { result in
                                NavigationLink(destination: destinationView(for: result)) {
                                    SearchResultRow(
                                        result: result,
                                        icon: symbolDetails(for: result.type)
                                    )
                                }
                            }
                        }
                    }
                } else {
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

                    if shouldShowInsights {
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
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Hi \(session.profile.firstName)")
            .navigationSubtitle(navigationSubtitleText)
            .searchable(text: $searchText, prompt: "Search locations, machines, SKUs...")
            .onSubmit(of: .search) {
                performSearch()
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty {
                    showingSearchResults = false
                    searchResults = []
                }
            }
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
            .overlay {
                if isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
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

    @ViewBuilder
    private func destinationView(for result: SearchResult) -> some View {
        switch result.type {
        case "machine":
            MachineDetailView(machineId: result.id, session: session)
        case "location":
            SearchLocationDetailView(locationId: result.id, session: session)
        case "sku":
            SkuDetailView(skuId: result.id, session: session)
        default:
            Text("Unknown result type")
        }
    }

    private func symbolDetails(for type: String) -> (systemName: String, color: Color) {
        switch type.lowercased() {
        case "machine":
            return ("building", .purple)
        case "sku":
            return ("tag", .teal)
        case "location":
            return ("mappin.circle", .orange)
        default:
            return ("magnifyingglass", .gray)
        }
    }

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showingSearchResults = false
            searchResults = []
            return
        }

        isSearching = true
        Task {
            do {
                let response = try await searchService.search(query: searchText)
                await MainActor.run {
                    searchResults = response.results
                    showingSearchResults = true
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    // Could show error message here
                }
            }
        }
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    let icon: (systemName: String, color: Color)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon.systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(icon.color)
                .frame(width: 36, height: 36)
                .background(icon.color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(primaryText)
                    .font(.headline)
                if let secondaryText, !secondaryText.isEmpty {
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var primaryText: String {
        switch result.type.lowercased() {
        case "machine":
            return result.subtitle.isEmpty ? result.title : result.subtitle
        case "sku":
            return skuName ?? (result.subtitle.isEmpty ? result.title : result.subtitle)
        default:
            return result.title
        }
    }

    private var secondaryText: String? {
        switch result.type.lowercased() {
        case "machine":
            return result.title
        case "sku":
            let detailText = skuDetails
            var parts: [String] = []
            if let detailText, !detailText.isEmpty {
                parts.append(detailText)
            }
            if !result.title.isEmpty {
                parts.append(result.title)
            }
            return parts.isEmpty ? nil : parts.joined(separator: " • ")
        default:
            return result.subtitle.isEmpty ? nil : result.subtitle
        }
    }

    private var skuName: String? {
        skuSubtitleComponents.first
    }

    private var skuDetails: String? {
        let details = skuSubtitleComponents.dropFirst().joined(separator: " • ")
        return details.isEmpty ? nil : details
    }

    private var skuSubtitleComponents: [String] {
        result.subtitle
            .split(separator: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
