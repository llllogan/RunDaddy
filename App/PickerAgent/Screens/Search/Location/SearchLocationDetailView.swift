import SwiftUI

struct SearchLocationDetailView: View {
    let locationId: String
    let session: AuthSession

    @State private var location: Location?
    @State private var locationStats: LocationStatsResponse?
    @State private var isLoading = true
    @State private var isLoadingStats = true
    @State private var errorMessage: String?
    @State private var selectedPeriod: SkuPeriod = .week
    @State private var selectedBreakdown: LocationChartBreakdown = .machines
    @State private var machineDetailNavigationId: String?
    @State private var skuDetailNavigationId: String?

    private let locationsService: LocationsServicing = LocationsService()

    var body: some View {
        List {
            if isLoading && location == nil {
                Section {
                    ProgressView("Loading location details...")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if let errorMessage = errorMessage {
                Section {
                    VStack(spacing: 8) {
                        Text("Error")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                }
            } else if let location = location {
                Section {
                    if let stats = locationStats {
                        SearchLocationInfoBento(
                            location: location,
                            lastPacked: stats.lastPacked,
                            percentageChange: stats.percentageChange,
                            bestMachine: stats.bestMachine,
                            bestSku: stats.bestSku,
                            selectedPeriod: selectedPeriod,
                            onBestMachineTap: { navigateToMachineDetail($0) },
                            onBestSkuTap: { navigateToSkuDetail($0) }
                        )
                    } else if isLoadingStats {
                        ProgressView("Loading stats...")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text("We couldn't load stats for this location.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } header: {
                    Text("Location Overview")
                }
                .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if let stats = locationStats {
                    Section {
                        LocationStatsChartView(
                            stats: stats,
                            selectedPeriod: $selectedPeriod,
                            selectedBreakdown: $selectedBreakdown
                        )
                    } header: {
                        Text("Recent Activity")
                    }
                }
            }
        }
        .navigationTitle(locationDisplayTitle)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadLocationDetails()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Task {
                await loadLocationStats()
            }
        }
        .background(navigationLinks)
    }

    private func loadLocationDetails() async {
        isLoading = true
        do {
            location = try await locationsService.getLocation(id: locationId)
            isLoading = false
            await loadLocationStats()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadLocationStats() async {
        guard location != nil else { return }
        isLoadingStats = true
        do {
            locationStats = try await locationsService.getLocationStats(id: locationId, period: selectedPeriod)
        } catch {
            print("Failed to load location stats: \(error)")
            locationStats = nil
        }
        isLoadingStats = false
    }

    private var locationDisplayTitle: String {
        location?.name ?? "Location Details"
    }

    private func navigateToMachineDetail(_ machine: LocationBestMachine) {
        guard !machine.machineId.isEmpty else { return }
        machineDetailNavigationId = machine.machineId
    }

    private func navigateToSkuDetail(_ sku: LocationBestSku) {
        guard !sku.skuId.isEmpty else { return }
        skuDetailNavigationId = sku.skuId
    }

    @ViewBuilder
    private var navigationLinks: some View {
        VStack {
            NavigationLink(
                isActive: Binding(
                    get: { machineDetailNavigationId != nil },
                    set: { isActive in
                        if !isActive {
                            machineDetailNavigationId = nil
                        }
                    }
                ),
                destination: {
                    if let machineId = machineDetailNavigationId {
                        MachineDetailView(machineId: machineId, session: session)
                    } else {
                        EmptyView()
                    }
                },
                label: {
                    EmptyView()
                }
            )
            .hidden()

            NavigationLink(
                isActive: Binding(
                    get: { skuDetailNavigationId != nil },
                    set: { isActive in
                        if !isActive {
                            skuDetailNavigationId = nil
                        }
                    }
                ),
                destination: {
                    if let skuId = skuDetailNavigationId {
                        SkuDetailView(skuId: skuId, session: session)
                    } else {
                        EmptyView()
                    }
                },
                label: {
                    EmptyView()
                }
            )
            .hidden()
        }
    }
}
