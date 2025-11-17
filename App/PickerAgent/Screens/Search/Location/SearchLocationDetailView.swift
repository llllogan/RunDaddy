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
    @State private var skuNavigationTarget: SearchLocationSkuNavigation?
    @State private var machineNavigationTarget: SearchLocationMachineNavigation?
    @Environment(\.openURL) private var openURL
    @AppStorage(DirectionsApp.storageKey) private var preferredDirectionsAppRawValue = DirectionsApp.appleMaps.rawValue

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
                            machines: location.machines ?? [],
                            lastPacked: stats.lastPacked,
                            percentageChange: stats.percentageChange,
                            bestSku: stats.bestSku,
                            machineSalesShare: stats.machineSalesShare ?? [],
                            selectedPeriod: selectedPeriod,
                            onBestSkuTap: { navigateToSkuDetail($0) },
                            onMachineTap: { navigateToMachineDetail($0) }
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    openDirections()
                } label: {
                    Image(systemName: "map")
                }
                .disabled(locationDirectionsQuery == nil)
                .accessibilityLabel("Get directions")
            }
        }
        .navigationDestination(item: $skuNavigationTarget) { target in
            SkuDetailView(skuId: target.id, session: session)
        }
        .navigationDestination(item: $machineNavigationTarget) { target in
            MachineDetailView(machineId: target.id, session: session)
        }
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

    private func navigateToSkuDetail(_ sku: LocationBestSku) {
        guard !sku.skuId.isEmpty else { return }
        skuNavigationTarget = SearchLocationSkuNavigation(id: sku.skuId)
    }

    private func navigateToMachineDetail(_ machine: LocationMachine) {
        guard !machine.id.isEmpty else { return }
        machineNavigationTarget = SearchLocationMachineNavigation(id: machine.id)
    }

    private var preferredDirectionsApp: DirectionsApp {
        DirectionsApp(rawValue: preferredDirectionsAppRawValue) ?? .appleMaps
    }

    private var locationDirectionsQuery: String? {
        guard let location else { return nil }
        let trimmedAddress = location.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedAddress.isEmpty {
            return trimmedAddress
        }

        let trimmedName = location.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private func openDirections() {
        guard let query = locationDirectionsQuery,
              let targetURL = preferredDirectionsApp.url(for: query) else {
            return
        }

        openURL(targetURL) { accepted in
            guard !accepted,
                  preferredDirectionsApp == .waze,
                  let fallbackURL = DirectionsApp.appleMaps.url(for: query) else {
                return
            }
            openURL(fallbackURL)
        }
    }
}

private struct SearchLocationSkuNavigation: Identifiable, Hashable {
    let id: String
}

private struct SearchLocationMachineNavigation: Identifiable, Hashable {
    let id: String
}
