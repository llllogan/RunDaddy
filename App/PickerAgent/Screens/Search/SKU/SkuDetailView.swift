import SwiftUI

struct SkuDetailView: View {
    let skuId: String
    let session: AuthSession
    
    @State private var sku: SKU?
    @State private var skuStats: SkuStatsResponse?
    @State private var isLoading = true
    @State private var isLoadingStats = true
    @State private var skuBreakdown: PickEntryBreakdown?
    @State private var breakdownFilters = PickEntryBreakdown.AvailableFilters(sku: [], machine: [], location: [])
    @State private var isLoadingBreakdown = true
    @State private var breakdownError: String?
    @State private var errorMessage: String?
    @State private var selectedPeriod: SkuPeriod = .week
    @State private var isUpdatingCheeseStatus = false
    @State private var selectedLocationFilter: String?
    @State private var selectedMachineFilter: String?
    @State private var machineNavigationTarget: SkuDetailMachineNavigation?
    
    private let skusService = SkusService()
    private let analyticsService = AnalyticsService()
    
    var body: some View {
        List {
            if isLoading && sku == nil {
                Section {
                    ProgressView("Loading SKU details...")
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
            } else if let sku = sku {
                // SKU Information Section
                Section {
                    if let skuStats = skuStats {
                        SkuInfoBento(
                            sku: sku,
                            isUpdatingCheeseStatus: isUpdatingCheeseStatus,
                            onToggleCheeseStatus: { toggleCheeseStatus() },
                            mostRecentPick: skuStats.mostRecentPick,
                            percentageChange: skuStats.percentageChange,
                            bestMachine: skuStats.bestMachine,
                            selectedPeriod: selectedPeriod,
                            onBestMachineTap: { bestMachine in
                                navigateToMachineDetail(bestMachine)
                            }
                        )
                    } else if isLoadingStats {
                        ProgressView("Loading SKU stats...")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text("We couldn't load SKU stats right now.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } header: {
                    Text("SKU Details")
                        .padding(.leading, 16)
                }
                .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    SkuStatsChartView(
                        breakdown: skuBreakdown,
                        availableFilters: breakdownFilters,
                        isLoading: isLoadingBreakdown,
                        errorMessage: breakdownError,
                        selectedPeriod: $selectedPeriod,
                        selectedLocationFilter: $selectedLocationFilter,
                        selectedMachineFilter: $selectedMachineFilter,
                        onFilterChange: { locationId, machineId in
                            await applySkuStatsFilters(locationId: locationId, machineId: machineId)
                        }
                    )
                } header: {
                    Text("Recent Activity")
                }
            }
        }
        .navigationTitle(skuDisplayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSkuDetails()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Task {
                await loadSkuStats()
                await loadSkuBreakdown()
            }
        }
        .navigationDestination(item: $machineNavigationTarget) { target in
            MachineDetailView(machineId: target.id, session: session)
        }
    }
    
    private func loadSkuDetails() async {
        do {
            sku = try await skusService.getSku(id: skuId)
            isLoading = false
            
            // Load stats after SKU details are loaded
            await loadSkuStats()
            await loadSkuBreakdown()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func loadSkuStats() async {
        isLoadingStats = true
        do {
            skuStats = try await skusService.getSkuStats(
                id: skuId,
                period: selectedPeriod,
                locationId: selectedLocationFilter,
                machineId: selectedMachineFilter
            )
        } catch {
            // Don't show error for stats failure, just log it
            print("Failed to load SKU stats: \(error)")
        }
        isLoadingStats = false
    }

    private func loadSkuBreakdown() async {
        isLoadingBreakdown = true
        breakdownError = nil

        do {
            let response = try await analyticsService.fetchPickEntryBreakdown(
                aggregation: selectedPeriod.pickEntryAggregation,
                focus: PickEntryBreakdown.ChartItemFocus(skuId: skuId, machineId: nil, locationId: nil),
                filters: PickEntryBreakdown.Filters(
                    skuIds: [skuId],
                    machineIds: selectedMachineFilter.map { [$0] } ?? [],
                    locationIds: selectedLocationFilter.map { [$0] } ?? []
                ),
                showBars: selectedPeriod.pickEntryAggregation.defaultBars,
                credentials: session.credentials
            )
            skuBreakdown = response
            breakdownFilters = response.availableFilters
        } catch let authError as AuthError {
            breakdownError = authError.localizedDescription
            skuBreakdown = nil
            breakdownFilters = PickEntryBreakdown.AvailableFilters(sku: [], machine: [], location: [])
        } catch let analyticsError as AnalyticsServiceError {
            breakdownError = analyticsError.localizedDescription
            skuBreakdown = nil
            breakdownFilters = PickEntryBreakdown.AvailableFilters(sku: [], machine: [], location: [])
        } catch {
            breakdownError = "We couldn't load chart data right now."
            skuBreakdown = nil
            breakdownFilters = PickEntryBreakdown.AvailableFilters(sku: [], machine: [], location: [])
        }

        isLoadingBreakdown = false
    }
    
    private func applySkuStatsFilters(locationId: String?, machineId: String?) async {
        let didChange = selectedLocationFilter != locationId || selectedMachineFilter != machineId
        if !didChange {
            return
        }
        selectedLocationFilter = locationId
        selectedMachineFilter = machineId
        await loadSkuStats()
        await loadSkuBreakdown()
    }
    
    private func toggleCheeseStatus() {
        guard let sku = sku else { return }
        
        isUpdatingCheeseStatus = true
        Task {
            do {
                try await skusService.updateCheeseStatus(
                    id: sku.id,
                    isCheeseAndCrackers: !sku.isCheeseAndCrackers
                )
                
                // Refresh SKU details to get updated status
                await loadSkuDetails()
            } catch {
                // Could show error alert here
                print("Failed to update cheese status: \(error)")
            }
            isUpdatingCheeseStatus = false
        }
    }
    
    private var skuDisplayTitle: String {
        if let name = sku?.name, !name.isEmpty {
            return name
        }
        if let code = sku?.code, !code.isEmpty {
            return code
        }
        return "SKU Details"
    }

    private func navigateToMachineDetail(_ bestMachine: SkuBestMachine) {
        guard !bestMachine.machineId.isEmpty else { return }
        machineNavigationTarget = SkuDetailMachineNavigation(id: bestMachine.machineId)
    }
}

private struct SkuDetailMachineNavigation: Identifiable, Hashable {
    let id: String
}
