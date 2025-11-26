import SwiftUI

struct MachineDetailView: View {
    let machineId: String
    let session: AuthSession

    @State private var machine: Machine?
    @State private var machineStats: MachineStatsResponse?
    @State private var isLoading = true
    @State private var isLoadingStats = true
    @State private var machineBreakdown: PickEntryBreakdown?
    @State private var isLoadingBreakdown = true
    @State private var breakdownError: String?
    @State private var errorMessage: String?
    @State private var selectedPeriod: SkuPeriod = .week
    @State private var skuNavigationTarget: MachineDetailSkuNavigation?
    @State private var locationNavigationTarget: MachineDetailLocationNavigation?

    private let machinesService = MachinesService()
    private let analyticsService = AnalyticsService()

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
                            selectedPeriod: selectedPeriod,
                            onBestSkuTap: { bestSku in
                                navigateToSkuDetail(bestSku)
                            },
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
                            selectedPeriod: selectedPeriod,
                            onBestSkuTap: nil,
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

                Section {
                    MachineStatsChartView(
                        breakdown: machineBreakdown,
                        isLoading: isLoadingBreakdown,
                        errorMessage: breakdownError,
                        selectedPeriod: $selectedPeriod
                    )
                } header: {
                    Text("Recent Activity")
                }
            }
        }
        .navigationTitle(machineDisplayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMachineDetails()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Task {
                await loadMachineStats()
                await loadMachineBreakdown()
            }
        }
        .navigationDestination(item: $skuNavigationTarget) { target in
            SkuDetailView(skuId: target.id, session: session)
        }
        .navigationDestination(item: $locationNavigationTarget) { target in
            SearchLocationDetailView(locationId: target.id, session: session)
        }
    }

    private func loadMachineDetails() async {
        do {
            machine = try await machinesService.getMachine(id: machineId)
            isLoading = false
            await loadMachineStats()
            await loadMachineBreakdown()
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

    private func loadMachineBreakdown() async {
        isLoadingBreakdown = true
        breakdownError = nil

        do {
            let response = try await analyticsService.fetchPickEntryBreakdown(
                aggregation: selectedPeriod.pickEntryAggregation,
                focus: PickEntryBreakdown.ChartItemFocus(skuId: nil, machineId: machineId, locationId: nil),
                filters: PickEntryBreakdown.Filters(
                    skuIds: [],
                    machineIds: [machineId],
                    locationIds: []
                ),
                showBars: selectedPeriod.pickEntryAggregation.defaultBars,
                credentials: session.credentials
            )
            machineBreakdown = response
        } catch let authError as AuthError {
            breakdownError = authError.localizedDescription
            machineBreakdown = nil
        } catch let analyticsError as AnalyticsServiceError {
            breakdownError = analyticsError.localizedDescription
            machineBreakdown = nil
        } catch {
            breakdownError = "We couldn't load chart data right now."
            machineBreakdown = nil
        }

        isLoadingBreakdown = false
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
