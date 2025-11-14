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

    private let machinesService = MachinesService()

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
                            onBestSkuTap: nil
                        )
                    }
                } header: {
                    Text("Machine Information")
                }
                .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if let machineStats = machineStats {
                    Section {
                        MachineStatsChartView(
                            stats: machineStats,
                            selectedPeriod: $selectedPeriod
                        )
                    } header: {
                        Text("Recent Activity")
                    }
                }
            }
        }
        .navigationTitle(machineDisplayTitle)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadMachineDetails()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Task {
                await loadMachineStats()
            }
        }
        .navigationDestination(item: $skuNavigationTarget) { target in
            SkuDetailView(skuId: target.id, session: session)
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
}

private struct MachineDetailSkuNavigation: Identifiable, Hashable {
    let id: String
}
