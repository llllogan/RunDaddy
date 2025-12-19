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
    @State private var selectedRun: SelectedRunDestination?
    @State private var showChocolateBoxesChip = true
    private let authService: AuthServicing = AuthService()
    
    init(session: AuthSession) {
        self.session = session
        _viewModel = StateObject(wrappedValue: AllRunsViewModel(session: session))
    }

    var body: some View {
        List {
            if let message = viewModel.errorMessage {
                Section {
                    ErrorStateRow(message: message)
                }
            }

            if viewModel.isLoading && viewModel.runsByDate.isEmpty {
                LoadingStateRow()
            } else if viewModel.runsByDate.isEmpty {
                EmptyStateRow(message: "No runs found")
            } else {
                ForEach(Array(viewModel.runsByDate.enumerated()), id: \.element.date) { index, dateSection in
                    if pastRunsInsertionIndex == index {
                        pastRunsTitleRow
                    }
                    let showPackedByYouChip = !dateSection.runs.contains { $0.runner?.id == session.credentials.userID }
                    Section(dateSection.headerText) {
                        if dateSection.kind == .today || dateSection.kind == .tomorrow {
                            StaggeredBentoGrid(
                                items: bentoItems(
                                    for: dateSection.runs,
                                    showPackedByYouChip: showPackedByYouChip,
                                    showChocolateBoxesChip: showChocolateBoxesChip
                                ),
                                columnCount: 2
                            )
                                .padding(.vertical, 2)
                                .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(dateSection.runs) { run in
                                NavigationLink {
                                    RunDetailView(runId: run.id, session: session)
                                } label: {
                                    RunRow(
                                        run: run,
                                        currentUserId: session.credentials.userID,
                                        showPackedByYouChip: showPackedByYouChip,
                                        showChocolateBoxesChip: showChocolateBoxesChip
                                    )
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
        }
        .listStyle(.insetGrouped)
        .navigationTitle("All Runs")
        .navigationDestination(item: $selectedRun) { destination in
            RunDetailView(runId: destination.id, session: session)
        }
        .task {
            await loadCompanyVisibility()
            await viewModel.loadRuns()
        }
        .onAppear {
            Task {
                await loadCompanyVisibility()
            }
        }
        .onChange(of: session) { _, newSession in
            viewModel.resetForNewSession(newSession)
            Task {
                await loadCompanyVisibility()
                await viewModel.loadRuns(force: true)
            }
        }
        .refreshable {
            await loadCompanyVisibility()
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

    private var pastRunsInsertionIndex: Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let todayIndex = viewModel.runsByDate.firstIndex(where: { calendar.isDateInToday($0.date) })
        let firstPastIndex = viewModel.runsByDate.firstIndex(where: { $0.date < today })

        guard let todayIndex, let firstPastIndex else {
            return nil
        }

        return firstPastIndex > todayIndex ? firstPastIndex : nil
    }

    private var pastRunsTitleRow: some View {
        Text("Past Runs")
            .font(.title.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(.init(top: 2, leading: 6, bottom: 2, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func bentoItems(for runs: [RunSummary], showPackedByYouChip: Bool, showChocolateBoxesChip: Bool) -> [BentoItem] {
        runs.map { run in
            BentoItem(
                id: "run-summary-\(run.id)",
                title: "\(run.locationCount) \(run.locationCount == 1 ? "Location" : "Locations")",
                value: "",
                subtitle: "View",
                symbolName: "flag.checkered",
                symbolTint: .secondary,
                showsSymbol: false,
                titleIsProminent: true,
                allowsMultilineValue: true,
                onTap: { selectedRun = SelectedRunDestination(id: run.id) },
                showsChevron: true,
                customContent: AnyView(
                    RunSummaryInfoChips(
                        run: run,
                        currentUserId: session.credentials.userID,
                        showPackedByYouChip: showPackedByYouChip,
                        showChocolateBoxesChip: showChocolateBoxesChip
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contextMenu {
                            Button(role: .destructive) {
                                runToDelete = run
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                )
            )
        }
    }
    
    private func loadCompanyVisibility() async {
        do {
            let profile = try await authService.fetchCurrentUserProfile(credentials: session.credentials)
            showChocolateBoxesChip = profile.currentCompany?.showChocolateBoxes ?? true
        } catch {
            showChocolateBoxesChip = true
        }
    }
}

private struct RunDateSection: Identifiable {
    enum Kind: Equatable {
        case today
        case tomorrow
        case other
    }

    let id = UUID()
    let date: Date
    let runs: [RunSummary]

    var kind: Kind {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return .today
        }
        if calendar.isDateInTomorrow(date) {
            return .tomorrow
        }
        return .other
    }
    
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

private struct SelectedRunDestination: Identifiable, Hashable {
    let id: String
}

@MainActor
fileprivate final class AllRunsViewModel: ObservableObject {
    @Published private(set) var runsByDate: [RunDateSection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var session: AuthSession
    let service: RunsServicing
    private var historyStartOffset: Int {
        let normalizedRole = session.profile.role?.uppercased() ?? ""
        let isPicker = normalizedRole == "PICKER"
        return isPicker ? 0 : -100
    }
    private var isLighthouse: Bool {
        (session.profile.role?.uppercased() ?? "") == "LIGHTHOUSE"
    }

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
            let allRuns = try await service.fetchAllRuns(
                startDayOffset: historyStartOffset,
                endDayOffset: nil,
                companyId: nil,
                credentials: session.credentials
            )
            
            // Group runs by date
            let groupedRuns = Dictionary(grouping: allRuns) { run in
                let calendar = Calendar.current
                let date = run.scheduledFor ?? run.createdAt
                return calendar.startOfDay(for: date)
            }

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())

            var todayDate: Date?
            var futureDates: [Date] = []
            var pastDates: [Date] = []

            for date in groupedRuns.keys {
                if calendar.isDate(date, inSameDayAs: today) {
                    todayDate = date
                } else if date > today {
                    futureDates.append(date)
                } else {
                    pastDates.append(date)
                }
            }

            futureDates.sort(by: >)
            pastDates.sort(by: >)

            var orderedDates: [Date] = []
            orderedDates.append(contentsOf: futureDates)
            if let todayDate {
                orderedDates.append(todayDate)
            }
            orderedDates.append(contentsOf: pastDates)

            runsByDate = orderedDates.map { date in
                let runsForDate = (groupedRuns[date] ?? []).sorted { lhs, rhs in
                    let lhsDate = lhs.scheduledFor ?? lhs.createdAt
                    let rhsDate = rhs.scheduledFor ?? rhs.createdAt
                    return lhsDate < rhsDate
                }
                return RunDateSection(date: date, runs: runsForDate)
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

    func handleCompanyChange() {
        Task { await loadRuns(force: true) }
    }

    func updateSession(_ session: AuthSession) {
        self.session = session
    }

    func resetForNewSession(_ session: AuthSession) {
        self.session = session
        runsByDate = []
        errorMessage = nil
        isLoading = false
        handleCompanyChange()
    }
    
    private func companyIdFromToken() -> String? {
        decodeCompanyId(from: session.credentials.accessToken)
    }

    private func decodeCompanyId(from token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
        base64 = base64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 {
            base64.append(String(repeating: "=", count: padding))
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["companyId"] as? String
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
