import SwiftUI

struct MainTabView: View {
    let session: AuthSession
    let logoutAction: () -> Void

    @State private var isShowingProfile = false

    private var requiresCompanyContext: Bool {
        JwtPayload.companyId(from: session.credentials.accessToken) == nil
    }

    private var profileSheetPresented: Binding<Bool> {
        Binding(
            get: { isShowingProfile || requiresCompanyContext },
            set: { newValue in
                guard !requiresCompanyContext else {
                    return
                }
                isShowingProfile = newValue
            }
        )
    }

    var body: some View {
        ZStack {
            if requiresCompanyContext {
                Color(.systemBackground)
                    .ignoresSafeArea()
            } else {
                tabView
            }
        }
        .sheet(isPresented: profileSheetPresented) {
            ProfileView(
                isPresentedAsSheet: true,
                showsDismissButton: !requiresCompanyContext,
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
            .interactiveDismissDisabled(requiresCompanyContext)
        }
        .onChange(of: requiresCompanyContext, initial: false) { _, newValue in
            if !newValue {
                isShowingProfile = false
            }
        }
    }
}

private extension MainTabView {
    var tabView: some View {
        TabView {
            Tab("Runs", systemImage: "truck.box") {
                RunsTab(
                    session: session,
                    isShowingProfile: $isShowingProfile
                )
                .id(session.credentials.accessToken)
            }
            
            Tab("Notes", systemImage: "list.bullet.clipboard") {
                NotesTab(
                    session: session,
                    isShowingProfile: $isShowingProfile
                )
                .id(session.credentials.accessToken)
            }

            Tab("Expiries", systemImage: "calendar") {
                ExpiriesTab(
                    session: session,
                    isShowingProfile: $isShowingProfile
                )
                .id(session.credentials.accessToken)
            }

            Tab("Analytics", systemImage: "chart.bar.fill") {
                AnalyticsTab(
                    session: session,
                    isShowingProfile: $isShowingProfile
                )
                .id(session.credentials.accessToken)
            }

            
            Tab(role: .search) {
                SearchTab(
                    session: session,
                    isShowingProfile: $isShowingProfile
                )
            }
        }
    }
}

private struct RunsTab: View {
    let session: AuthSession
    @Binding var isShowingProfile: Bool

    var body: some View {
        NavigationStack {
            AllRunsView(session: session)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        profileButton
                    }
                }
        }
    }

    private var profileButton: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isShowingProfile = true
            }
        } label: {
            Label("Profile", systemImage: "person.fill")
        }
    }
}

private struct AnalyticsTab: View {
    let session: AuthSession
    @Binding var isShowingProfile: Bool

    var body: some View {
        NavigationStack {
            AnalyticsView(session: session)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        profileButton
                    }
                }
        }
    }

    private var profileButton: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isShowingProfile = true
            }
        } label: {
            Label("Profile", systemImage: "person.fill")
        }
    }
}

private struct ExpiriesTab: View {
    let session: AuthSession
    @Binding var isShowingProfile: Bool

    var body: some View {
        NavigationStack {
            ExpiriesView(session: session)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        profileButton
                    }
                }
        }
    }

    private var profileButton: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isShowingProfile = true
            }
        } label: {
            Label("Profile", systemImage: "person.fill")
        }
    }
}

private struct NotesTab: View {
    let session: AuthSession
    @Binding var isShowingProfile: Bool

    var body: some View {
        NavigationStack {
            CompanyNotesView(session: session)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        profileButton
                    }
                }
        }
    }

    private var profileButton: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isShowingProfile = true
            }
        } label: {
            Label("Profile", systemImage: "person.fill")
        }
    }
}

private struct SearchTab: View {
    let session: AuthSession
    @Binding var isShowingProfile: Bool

    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var suggestions: [SearchResult] = []
    @State private var isSearching = false
    @State private var isLoadingSuggestions = false
    @State private var suggestionsErrorMessage: String?
    @State private var notifications: [InAppNotification] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool
    private let searchService = SearchService()

    private var isShowingSuggestions: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if isShowingSuggestions {
                    suggestionsSection()
                } else {
                    searchResultsSection()
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    profileButton
                }
            }
            .searchable(text: $searchText, prompt: "Search locations, machines, SKUs...")
            .searchFocused($isSearchFocused)
            .onSubmit(of: .search) {
                performSearch()
            }
            .onChange(of: searchText) { _, newValue in
                handleSearchTextChange(newValue)
            }
            .onChange(of: suggestionsErrorMessage) { _, _ in
                refreshNotifications()
            }
            .inAppNotifications(notifications) { notification in
                if notification.isDismissable && notification.message == suggestionsErrorMessage {
                    suggestionsErrorMessage = nil
                }
                notifications.removeAll(where: { $0.id == notification.id })
            }
            .overlay {
                if isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
                }
            }
            .onAppear {
                isSearchFocused = true
                if suggestions.isEmpty {
                    loadSuggestionsIfNeeded()
                }
            }
            .onDisappear {
                isSearchFocused = false
                searchDebounceTask?.cancel()
            }
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
                        EntityResultRow(result: result)
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
                        EntityResultRow(result: suggestion)
                    }
                }
            }
        }
    }

    private func handleSearchTextChange(_ newValue: String) {
        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResults = []
            searchDebounceTask?.cancel()
        } else {
            scheduleDebouncedSearch(for: newValue)
        }
    }

    private func refreshNotifications() {
        var items: [InAppNotification] = []

        if let message = suggestionsErrorMessage {
            items.append(
                InAppNotification(
                    message: message,
                    style: .info,
                    isDismissable: true
                )
            )
        }

        notifications = items
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

    @MainActor
    private func performSearch(query: String? = nil) {
        let trimmedQuery = (query ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchResults = []
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

    private var profileButton: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isShowingProfile = true
            }
        } label: {
            Label("Profile", systemImage: "person.fill")
        }
    }
}
