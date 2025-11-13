import SwiftUI

struct SkuDetailView: View {
    let skuId: String
    let session: AuthSession
    
    @State private var sku: SKU?
    @State private var skuStats: SkuStatsResponse?
    @State private var isLoading = true
    @State private var isLoadingStats = true
    @State private var errorMessage: String?
    @State private var selectedPeriod: SkuPeriod = .week
    @State private var isUpdatingCheeseStatus = false
    
    private let skusService = SkusService()
    
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
                    SkuInfoBento(
                        sku: sku,
                        isUpdatingCheeseStatus: isUpdatingCheeseStatus,
                        onToggleCheeseStatus: { toggleCheeseStatus() }
                    )
                } header: {
                    Text("SKU Information")
                }
                .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle(sku?.code ?? "SKU Details")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadSkuDetails()
        }
    }
    
    private func loadSkuDetails() async {
        do {
            sku = try await skusService.getSku(id: skuId)
            isLoading = false
            
            // Load stats after SKU details are loaded
            await loadSkuStats()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func loadSkuStats() async {
        do {
            skuStats = try await skusService.getSkuStats(id: skuId)
            isLoadingStats = false
        } catch {
            // Don't show error for stats failure, just log it
            print("Failed to load SKU stats: \(error)")
            isLoadingStats = false
        }
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
}
