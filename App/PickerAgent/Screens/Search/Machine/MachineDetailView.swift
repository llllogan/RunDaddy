import SwiftUI

struct MachineDetailView: View {
    let machineId: String
    let session: AuthSession

    @State private var machine: Machine?
    @State private var machineStats: MachineStatsResponse?
    @State private var isLoading = true
    @State private var isLoadingStats = true
    @State private var errorMessage: String?
    @State private var selectedPeriod: SkuPeriod = .week
    @State private var skuNavigationTarget: MachineDetailSkuNavigation?
    @State private var locationNavigationTarget: MachineDetailLocationNavigation?
    @State private var effectiveRole: UserRole?
    @StateObject private var chartsViewModel: ChartsViewModel
    @State private var recentNotes: [Note] = []
    @State private var isLoadingNotes = false

    private let machinesService = MachinesService()
    private let authService: AuthServicing = AuthService()
    private let notesService: NotesServicing = NotesService()

    init(machineId: String, session: AuthSession) {
        self.machineId = machineId
        self.session = session
        _chartsViewModel = StateObject(wrappedValue: ChartsViewModel(session: session))
    }

    var body: some View {
        List {
            if isLoading && machine == nil {
                Section {
                    ProgressView("Loading machine details...")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if let errorMessage = errorMessage {
                Section {
                    VStack {
                        Text("Error")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                }
            } else if let machine = machine {
                Section {
                    if let machineStats = machineStats {
                        MachineInfoBento(
                            machine: machine,
                            stats: machineStats,
                            onLocationTap: { location in
                                navigateToLocationDetail(location)
                            }
                        )
                    } else if isLoadingStats {
                        ProgressView("Loading machine stats...")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        MachineInfoBento(
                            machine: machine,
                            stats: nil,
                            onLocationTap: { location in
                                navigateToLocationDetail(location)
                            }
                        )
                    }
                } header: {
                    Text("Machine Details")
                        .padding(.leading, 16)
                }
                .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if canViewRecentActivity {
                    Section {
                        SkuBreakdownChartView(
                            viewModel: chartsViewModel,
                            refreshTrigger: false,
                            showFilters: true,
                            showAggregationControls: false,
                            focus: PickEntryBreakdown.ChartItemFocus(skuId: nil, machineId: machineId, locationId: nil),
                            onAggregationChange: { newAgg in
                                selectedPeriod = SkuPeriod(aggregation: newAgg) ?? selectedPeriod
                            },
                            applyPadding: false
                        )
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 26.0))
                        
                        if let machineStats {
                            MachinePerformanceBento(
                                stats: machineStats,
                                selectedPeriod: selectedPeriod,
                                onBestSkuTap: { bestSku in
                                    navigateToSkuDetail(bestSku)
                                },
                                highMark: chartsViewModel.skuBreakdownHighMark,
                                lowMark: chartsViewModel.skuBreakdownLowMark,
                                aggregation: chartsViewModel.skuBreakdownAggregation,
                                timeZoneIdentifier: chartsViewModel.skuBreakdownTimeZone,
                                percentageChange: chartsViewModel.skuBreakdownPercentageChange
                            )
                            .listRowInsets(.init(top: 10, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } else if !isLoadingStats {
                            MachinePerformanceBento(
                                stats: nil,
                                selectedPeriod: selectedPeriod,
                                onBestSkuTap: nil,
                                highMark: chartsViewModel.skuBreakdownHighMark,
                                lowMark: chartsViewModel.skuBreakdownLowMark,
                                aggregation: chartsViewModel.skuBreakdownAggregation,
                                timeZoneIdentifier: chartsViewModel.skuBreakdownTimeZone,
                                percentageChange: chartsViewModel.skuBreakdownPercentageChange
                            )
                            .listRowInsets(.init(top: 10, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text("Recent Activity")
                    }
                }

                if !recentNotes.isEmpty {
                    Section("Notes") {
                        ForEach(recentNotes) { note in
                            NoteRowView(note: note)
                        }

                        NavigationLink("View all notes") {
                            CompanyNotesView(
                                session: session,
                                initialFilterTag: NoteTagOption(
                                    id: machineId,
                                    type: .machine,
                                    label: {
                                        let trimmed = machine.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                        return trimmed.isEmpty ? machine.code : trimmed
                                    }(),
                                    subtitle: machine.location?.name
                                )
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(machineDisplayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chartsViewModel.updateSkuBreakdownFocus(
                PickEntryBreakdown.ChartItemFocus(skuId: nil, machineId: machineId, locationId: nil)
            )
            chartsViewModel.skuBreakdownAggregation = selectedPeriod.pickEntryAggregation
            await loadEffectiveRole()
            await loadMachineDetails()
            await loadRecentNotes()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Task {
                await loadMachineStats()
                if chartsViewModel.skuBreakdownAggregation != selectedPeriod.pickEntryAggregation {
                    chartsViewModel.updateSkuBreakdownAggregation(selectedPeriod.pickEntryAggregation)
                }
            }
        }
        .navigationDestination(item: $skuNavigationTarget) { target in
            SkuDetailView(skuId: target.id, session: session)
        }
        .navigationDestination(item: $locationNavigationTarget) { target in
            SearchLocationDetailView(locationId: target.id, session: session)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(PickEntryBreakdown.Aggregation.allCases) { aggregation in
                        Button {
                            if let mapped = SkuPeriod(aggregation: aggregation) {
                                selectedPeriod = mapped
                            }
                        } label: {
                            HStack {
                                Text(aggregation.displayName)
                                if aggregation == chartsViewModel.skuBreakdownAggregation {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(selectedPeriod.displayName, systemImage: "calendar")
                }
            }
        }
    }

    private func loadMachineDetails() async {
        do {
            machine = try await machinesService.getMachine(id: machineId)
            isLoading = false
            await loadMachineStats()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadMachineStats() async {
        isLoadingStats = true
        do {
            machineStats = try await machinesService.getMachineStats(
                id: machineId,
                period: selectedPeriod
            )
        } catch {
            print("Failed to load machine stats: \(error)")
            machineStats = nil
        }
        isLoadingStats = false
    }

    private func loadRecentNotes() async {
        if isLoadingNotes {
            return
        }

        isLoadingNotes = true
        defer { isLoadingNotes = false }

        do {
            let response = try await notesService.fetchNotes(
                targetType: .machine,
                targetId: machineId,
                limit: 5,
                offset: nil,
                credentials: session.credentials
            )
            recentNotes = Array(response.notes.prefix(5))
        } catch {
            recentNotes = []
        }
    }

    private var machineDisplayTitle: String {
        if let description = machine?.description, !description.isEmpty {
            return description
        }
        if let code = machine?.code, !code.isEmpty {
            return code
        }
        return "Machine Details"
    }

    private var canViewRecentActivity: Bool {
        guard let role = resolvedRole else { return false }
        return role == .admin || role == .owner || role == .god
    }

    private var resolvedRole: UserRole? {
        if let effectiveRole {
            return effectiveRole
        }
        guard let raw = session.profile.role?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() else {
            return nil
        }
        return UserRole(rawValue: raw)
    }

    private func loadEffectiveRole() async {
        do {
            let profile = try await authService.fetchCurrentUserProfile(credentials: session.credentials)
            if let companyRole = profile.currentCompany?.role
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased(),
               let userRole = UserRole(rawValue: companyRole) {
                effectiveRole = userRole
                return
            }
            if let userRoleValue = profile.role?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased(),
               let userRole = UserRole(rawValue: userRoleValue) {
                effectiveRole = userRole
            }
        } catch {
            // Leave effectiveRole nil on failure; guard will default to hiding.
            print("Failed to load effective role: \(error)")
        }
    }

    private func navigateToSkuDetail(_ bestSku: MachineBestSku) {
        guard !bestSku.skuId.isEmpty else { return }
        skuNavigationTarget = MachineDetailSkuNavigation(id: bestSku.skuId)
    }

    private func navigateToLocationDetail(_ location: Location) {
        guard !location.id.isEmpty else { return }
        locationNavigationTarget = MachineDetailLocationNavigation(id: location.id)
    }
}

private struct MachineDetailSkuNavigation: Identifiable, Hashable {
    let id: String
}

private struct MachineDetailLocationNavigation: Identifiable, Hashable {
    let id: String
}
