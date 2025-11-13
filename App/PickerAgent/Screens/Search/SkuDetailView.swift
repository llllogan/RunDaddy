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
                
                // Statistics Section
                Section {
                    if isLoadingStats {
                        ProgressView("Loading statistics...")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let stats = skuStats {
                        // Period selector
                        Picker("Period", selection: $selectedPeriod) {
                            Text("Week").tag(SkuPeriod.week)
                            Text("Month").tag(SkuPeriod.month)
                            Text("Quarter").tag(SkuPeriod.quarter)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        
                        // Chart
                        SkuStatsChartView(stats: stats, selectedPeriod: $selectedPeriod)
                            .listRowBackground(Color.clear)
                            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                        
                        // Performance Metrics
                        SkuStatsBento(
                            mostRecentPick: stats.mostRecentPick,
                            weekChange: stats.percentageChanges.week,
                            monthChange: stats.percentageChanges.month,
                            quarterChange: stats.percentageChanges.quarter
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Statistics")
                }
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

struct SkuInfoBento: View {
    let sku: SKU
    let isUpdatingCheeseStatus: Bool
    let onToggleCheeseStatus: () -> Void
    
    private var items: [BentoItem] {
        var cards: [BentoItem] = []
        
        cards.append(
            BentoItem(title: "Code",
                      value: sku.code,
                      symbolName: "barcode",
                      symbolTint: .blue)
        )
        
        cards.append(
            BentoItem(title: "Name",
                      value: sku.name,
                      symbolName: "tag",
                      symbolTint: .green,
                      allowsMultilineValue: true)
        )
        
        cards.append(
            BentoItem(title: "Type",
                      value: sku.type,
                      symbolName: "cube.box",
                      symbolTint: .orange)
        )
        
        cards.append(
            BentoItem(title: "Category",
                      value: sku.category ?? "None",
                      symbolName: "folder",
                      symbolTint: .purple)
        )
        
        cards.append(
            BentoItem(title: "Cheese & Crackers",
                      value: sku.isCheeseAndCrackers ? "Enabled" : "Disabled",
                      subtitle: "Tap to toggle",
                      symbolName: sku.isCheeseAndCrackers ? "checkmark.circle.fill" : "xmark.circle.fill",
                      symbolTint: sku.isCheeseAndCrackers ? .green : .red,
                      onTap: { onToggleCheeseStatus() },
                      showsChevron: false,
                      customContent: AnyView(
                        HStack {
                            if isUpdatingCheeseStatus {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text(sku.isCheeseAndCrackers ? "Enabled" : "Disabled")
                                    .font(.headline)
                                    .foregroundColor(sku.isCheeseAndCrackers ? .green : .red)
                            }
                            Spacer()
                            Image(systemName: sku.isCheeseAndCrackers ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(sku.isCheeseAndCrackers ? .green : .red)
                        }
                    ))
        )
        
        return cards
    }
    
    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
    }
}

struct SkuStatsBento: View {
    let mostRecentPick: MostRecentPick?
    let weekChange: SkuPercentageChange?
    let monthChange: SkuPercentageChange?
    let quarterChange: SkuPercentageChange?
    
    private var items: [BentoItem] {
        var cards: [BentoItem] = []
        
        if let mostRecentPick = mostRecentPick {
            cards.append(
                BentoItem(title: "Most Recent Pick",
                          value: formatDate(mostRecentPick.pickedAt),
                          subtitle: "\(mostRecentPick.locationName) • \(mostRecentPick.runId)",
                          symbolName: "clock",
                          symbolTint: .indigo,
                          allowsMultilineValue: true)
            )
        }
        
        cards.append(
            BentoItem(title: "Week Change",
                      value: formatPercentageChange(weekChange),
                      symbolName: trendSymbol(weekChange?.trend),
                      symbolTint: trendColor(weekChange?.trend),
                      isProminent: weekChange?.trend == "up")
        )
        
        cards.append(
            BentoItem(title: "Month Change",
                      value: formatPercentageChange(monthChange),
                      symbolName: trendSymbol(monthChange?.trend),
                      symbolTint: trendColor(monthChange?.trend),
                      isProminent: monthChange?.trend == "up")
        )
        
        cards.append(
            BentoItem(title: "Quarter Change",
                      value: formatPercentageChange(quarterChange),
                      symbolName: trendSymbol(quarterChange?.trend),
                      symbolTint: trendColor(quarterChange?.trend),
                      isProminent: quarterChange?.trend == "up")
        )
        
        return cards
    }
    
    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatPercentageChange(_ change: SkuPercentageChange?) -> String {
        guard let change = change else { return "No Data" }
        return String(format: "%@%.1f%%", change.value >= 0 ? "+" : "", change.value)
    }
    
    private func trendSymbol(_ trend: String?) -> String {
        switch trend {
        case "up":
            return "arrow.up"
        case "down":
            return "arrow.down"
        default:
            return "minus"
        }
    }
    
    private func trendColor(_ trend: String?) -> Color {
        switch trend {
        case "up":
            return .green
        case "down":
            return .red
        default:
            return .gray
        }
    }
}