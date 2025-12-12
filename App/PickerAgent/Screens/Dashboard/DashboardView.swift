//
//  Dashboard.swift
//  PickAgent
//
//  Created by Logan Janssen on 4/11/2025.
//

import SwiftUI

private enum SearchDisplayState {
    case dashboard
    case suggestions
    case results
}

struct DashboardView: View {
    let session: AuthSession
    let logoutAction: () -> Void

    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var momentumViewModel: DashboardMomentumViewModel
    @State private var isShowingProfile = false
    @State private var isShowingJoinCompany = false
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var suggestions: [SearchResult] = []
    @State private var isSearching = false
    @State private var isSearchPresented = false
    @State private var isLoadingSuggestions = false
    @State private var suggestionsErrorMessage: String?
    @State private var searchDisplayState: SearchDisplayState = .dashboard
    @State private var notifications: [InAppNotification] = []
    @State private var showingCompanyNotes = false
    private let searchService = SearchService()
    @State private var searchDebounceTask: Task<Void, Never>?

    private var hasCompany: Bool {
        viewModel.currentUserProfile?.hasCompany ?? true
    }

    private var shouldShowNoCompanyState: Bool {
        viewModel.currentUserProfile?.hasCompany == false
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
        viewModel.currentUserProfile?.hasCompany == true && !isPickerUser
    }

    private var totalRunsBentoItem: BentoItem? {
        guard let totalRuns = viewModel.totalRuns else {
            return nil
        }

        let formattedTotal = totalRuns.formatted(.number.grouping(.automatic))
        let formattedAverage = viewModel.averageRunsPerDay.map {
            $0.formatted(.number.precision(.fractionLength(1)))
        }

        return BentoItem(
            title: "All Time Total Runs",
            value: formattedTotal,
            callout: formattedAverage.map { "\($0)/day" },
            symbolName: "flag.checkered",
            symbolTint: Color.green,
            isProminent: true
        )
    }

    private var notesBentoItem: BentoItem {
        let value: String
        if let count = viewModel.recentNotesCount {
            value = "\(count)"
        } else if viewModel.isLoading {
            value = "…"
        } else {
            value = "0"
        }

        return BentoItem(
            title: "Notes",
            value: value,
            subtitle: "Today + yesterday",
            symbolName: "note.text",
            symbolTint: .purple,
            isProminent: true,
            onTap: {
                showingCompanyNotes = true
            },
            showsChevron: true
        )
    }

    private var navigationSubtitleText: String {
        let companyName = viewModel.currentUserProfile?.currentCompany?.name ?? "No Company"
        let dateString = Date().formatted(
            .dateTime
                .weekday(.wide)
                .month(.abbreviated)
                .day()
        )
        return "\(dateString), \(companyName)"
    }

    init(session: AuthSession, logoutAction: @escaping () -> Void) {
        self.session = session
        self.logoutAction = logoutAction
        _viewModel = StateObject(wrappedValue: DashboardViewModel(session: session))
        _momentumViewModel = StateObject(wrappedValue: DashboardMomentumViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasCompany {
                    dashboardList
                        .searchable(
                            text: $searchText,
                            isPresented: $isSearchPresented,
                            prompt: "Search locations, machines, SKUs..."
                        )
                        .onSubmit(of: .search) {
                            performSearch()
                        }
                        .onChange(of: searchText) { _, newValue in
                            if newValue.isEmpty {
                                searchResults = []
                                searchDisplayState = isSearchPresented ? .suggestions : .dashboard
                                searchDebounceTask?.cancel()
                            } else {
                                scheduleDebouncedSearch(for: newValue)
                            }
                        }
                        .onChange(of: isSearchPresented) { _, isPresented in
                            if isPresented {
                                searchResults = []
                                searchDisplayState = .suggestions
                                loadSuggestionsIfNeeded()
                            } else {
                                searchDisplayState = .dashboard
                                isSearching = false
                                searchText = ""
                                searchDebounceTask?.cancel()
                            }
                        }
                } else {
                    dashboardList
                }
            }
        }
        .task {
            await viewModel.loadRuns()
            await momentumViewModel.loadSnapshot()
            await momentumViewModel.loadPickEntryBreakdown()
        }
        .refreshable {
            await viewModel.loadRuns(force: true)
            await momentumViewModel.loadSnapshot(force: true)
            await momentumViewModel.loadPickEntryBreakdown(force: true)
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
        .fullScreenCover(isPresented: $isShowingJoinCompany) {
            JoinCompanyScannerView {
                Task {
                    await authViewModel.refreshSessionFromStoredCredentials()
                    await viewModel.loadRuns(force: true)
                    await momentumViewModel.loadSnapshot(force: true)
                }
            }
        }
        .onChange(of: session, initial: false) { _, newSession in
            viewModel.updateSession(newSession)
            momentumViewModel.updateSession(newSession)
            Task {
                await viewModel.loadRuns(force: true)
                await momentumViewModel.loadSnapshot(force: true)
                await momentumViewModel.loadPickEntryBreakdown(force: true)
            }
        }
        .onChange(of: hasCompany, initial: false) { _, newValue in
            if !newValue {
                resetSearchState()
            }
        }

    }

    private var dashboardList: some View {
        List {
            switch searchDisplayState {
            case .results:
                searchResultsSection()
            case .suggestions:
                suggestionsSection()
            case .dashboard:
                dashboardSections()
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(searchDisplayState == .dashboard ? "Hi \(session.profile.firstName)" : "Search")
        .navigationSubtitle(searchDisplayState == .dashboard ? navigationSubtitleText : "")
        .navigationBarTitleDisplayMode(.inline)
        .background(notesNavigationLink)
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
        .onDisappear {
            searchDebounceTask?.cancel()
        }
        .onChange(of: viewModel.errorMessage) { _, _ in
            refreshNotifications()
        }
        .onChange(of: momentumViewModel.errorMessage) { _, _ in
            refreshNotifications()
        }
        .onChange(of: suggestionsErrorMessage) { _, _ in
            refreshNotifications()
        }
        .onAppear {
            refreshNotifications()
        }
        .inAppNotifications(notifications) { notification in
            if notification.isDismissable && notification.message == suggestionsErrorMessage {
                suggestionsErrorMessage = nil
            }
            notifications.removeAll(where: { $0.id == notification.id })
        }
    }

    @ViewBuilder
    private func searchResultsSection() -> some View {
        Section("Results") {
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
    }

    @ViewBuilder
    private func suggestionsSection() -> some View {
        Section("Suggestions") {
            if isLoadingSuggestions {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading suggestions…")
                        .foregroundStyle(.secondary)
                }
            } else if suggestionsErrorMessage != nil {
                Text("Suggestions are unavailable right now.")
                    .foregroundStyle(.secondary)
            } else if suggestions.isEmpty {
                Text("No suggestions are available yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(suggestions) { suggestion in
                    NavigationLink(destination: destinationView(for: suggestion)) {
                        SearchResultRow(
                            result: suggestion,
                            icon: symbolDetails(for: suggestion.type)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dashboardSections() -> some View {
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

        if shouldShowNoCompanyState {
            NoCompanyMembershipSection {
                handleJoinCompanyTap()
            }
        }

        if shouldShowInsights {
            Section() {
                if let snapshot = momentumViewModel.snapshot {
                    DashboardMomentumBentoView(
                        snapshot: snapshot,
                        pickEntryBreakdown: momentumViewModel.pickEntryBreakdown,
                        onAnalyticsTap: nil
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    
                    NavigationLink {
                        AnalyticsView(session: session)
                    } label: {
                        HStack {
                            Text("View more Statistics")
                                .foregroundStyle(.primary)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                    
                    if let totalRunsItem = totalRunsBentoItem {
                        StaggeredBentoGrid(items: [totalRunsItem], columnCount: 1)
                            .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                    } else if viewModel.isLoading {
                        LoadingStateRow()
                            .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                    
                    NavigationLink {
                        AllRunsView(session: session)
                    } label: {
                        HStack {
                            Text("View all Runs")
                                .foregroundStyle(.primary)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                    
                } else if momentumViewModel.isLoading {
                    LoadingStateRow()
                } else if momentumViewModel.errorMessage != nil {
                    EmptyStateRow(message: "Insights are unavailable right now.")
                } else {
                    EmptyStateRow(message: "Momentum data will appear once this week's picks get underway.")
                }
            }
        }

        if hasCompany {
            Section("Notes") {
                StaggeredBentoGrid(items: [notesBentoItem], columnCount: 1)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func handleJoinCompanyTap() {
        isShowingJoinCompany = true
    }

    private func refreshNotifications() {
        var items: [InAppNotification] = []

        if let message = viewModel.errorMessage {
            items.append(
                InAppNotification(
                    message: message,
                    style: .error,
                    isDismissable: true
                )
            )
        }

        if let message = momentumViewModel.errorMessage {
            items.append(
                InAppNotification(
                    message: message,
                    style: .warning,
                    isDismissable: true
                )
            )
        }

        if let message = momentumViewModel.breakdownError {
            items.append(
                InAppNotification(
                    message: message,
                    style: .warning,
                    isDismissable: true
                )
            )
        }

        if let message = suggestionsErrorMessage {
            items.append(
                InAppNotification(
                    message: message,
                    style: .info
                )
            )
        }

        notifications = items
    }

    private func resetSearchState() {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        searchText = ""
        searchResults = []
        suggestions = []
        suggestionsErrorMessage = nil
        isSearchPresented = false
        isSearching = false
        isLoadingSuggestions = false
        searchDisplayState = .dashboard
    }

    private func scheduleDebouncedSearch(for text: String) {
        searchDebounceTask?.cancel()
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }
        searchDebounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                performSearch(query: trimmedText)
            }
        }
    }

    private func loadSuggestionsIfNeeded(force: Bool = false) {
        if isLoadingSuggestions || (suggestions.isEmpty == false && !force) {
            return
        }
        isLoadingSuggestions = true
        suggestionsErrorMessage = nil
        Task {
            do {
                let response = try await searchService.fetchSuggestions(lookbackDays: nil)
                await MainActor.run {
                    suggestions = response.results
                    isLoadingSuggestions = false
                }
            } catch {
                await MainActor.run {
                    suggestionsErrorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "Unable to load suggestions right now."
                    isLoadingSuggestions = false
                }
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

    @MainActor
    private func performSearch(query: String? = nil) {
        let trimmedQuery = (query ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            searchResults = []
            searchDisplayState = isSearchPresented ? .suggestions : .dashboard
            isSearching = false
            return
        }

        isSearching = true
        searchResults = []
        searchDisplayState = .results
        let activeQuery = trimmedQuery
        Task {
            do {
                let response = try await searchService.search(query: activeQuery)
                await MainActor.run {
                    guard activeQuery == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                        return
                    }
                    searchResults = sortedSearchResults(response.results, for: activeQuery)
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    guard activeQuery == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                        return
                    }
                    isSearching = false
                    searchResults = []
                }
            }
        }
    }

    private func sortedSearchResults(_ results: [SearchResult], for query: String) -> [SearchResult] {
        guard shouldPrioritizeSkus(query: query) else {
            return results
        }

        let priorities: [String: Int] = [
            "sku": 0,
            "machine": 1,
            "location": 2,
        ]

        return results.sorted { lhs, rhs in
            let lhsPriority = priorities[lhs.type.lowercased()] ?? 3
            let rhsPriority = priorities[rhs.type.lowercased()] ?? 3

            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func shouldPrioritizeSkus(query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return false
        }

        if normalizedQuery.hasPrefix("sku") {
            return true
        }

        if normalizedQuery.contains("-") {
            return true
        }

        return normalizedQuery.rangeOfCharacter(from: .decimalDigits) != nil
    }
}

private extension DashboardView {
    var notesNavigationLink: some View {
        NavigationLink(
            destination: CompanyNotesView(session: session) { updatedCount in
                viewModel.recentNotesCount = updatedCount
            },
            isActive: $showingCompanyNotes
        ) {
            EmptyView()
        }
        .hidden()
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
