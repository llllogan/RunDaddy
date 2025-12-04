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
    @State private var isUpdatingWeight = false
    @State private var isShowingWeightAlert = false
    @State private var weightInputText = ""
    @State private var weightUpdateError: String?
    @State private var machineNavigationTarget: SkuDetailMachineNavigation?
    @State private var effectiveRole: UserRole?
    @StateObject private var chartsViewModel: ChartsViewModel
    
    private let skusService = SkusService()
    private let authService: AuthServicing = AuthService()

    init(skuId: String, session: AuthSession) {
        self.skuId = skuId
        self.session = session
        _chartsViewModel = StateObject(wrappedValue: ChartsViewModel(session: session))
    }
    
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
                            mostRecentPick: skuStats.mostRecentPick
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

                if canViewRecentActivity {
                    Section {
                        SkuBreakdownChartView(
                            viewModel: chartsViewModel,
                            refreshTrigger: false,
                            showFilters: true,
                            focus: PickEntryBreakdown.ChartItemFocus(skuId: skuId, machineId: nil, locationId: nil),
                            onAggregationChange: { newAgg in
                                if let mapped = SkuPeriod(aggregation: newAgg) {
                                    selectedPeriod = mapped
                                }
                            },
                            applyPadding: false
                        )
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 26.0))

                        if let skuStats {
                            SkuPerformanceBento(
                                percentageChange: chartsViewModel.skuBreakdownPercentageChange,
                                bestMachine: skuStats.bestMachine,
                                selectedPeriod: selectedPeriod,
                                onBestMachineTap: { bestMachine in
                                    navigateToMachineDetail(bestMachine)
                                },
                                highMark: chartsViewModel.skuBreakdownHighMark,
                                lowMark: chartsViewModel.skuBreakdownLowMark,
                                aggregation: chartsViewModel.skuBreakdownAggregation,
                                timeZoneIdentifier: chartsViewModel.skuBreakdownTimeZone
                            )
                            .listRowInsets(.init(top: 10, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } else if !isLoadingStats {
                            SkuPerformanceBento(
                                percentageChange: chartsViewModel.skuBreakdownPercentageChange,
                                bestMachine: nil,
                                selectedPeriod: selectedPeriod,
                                onBestMachineTap: nil,
                                highMark: chartsViewModel.skuBreakdownHighMark,
                                lowMark: chartsViewModel.skuBreakdownLowMark,
                                aggregation: chartsViewModel.skuBreakdownAggregation,
                                timeZoneIdentifier: chartsViewModel.skuBreakdownTimeZone
                            )
                            .listRowInsets(.init(top: 10, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text("Recent Activity")
                    }
                }
            }
        }
        .navigationTitle(skuDisplayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chartsViewModel.updateSkuBreakdownFocus(
                PickEntryBreakdown.ChartItemFocus(skuId: skuId, machineId: nil, locationId: nil)
            )
            chartsViewModel.skuBreakdownAggregation = selectedPeriod.pickEntryAggregation
            await loadEffectiveRole()
            await loadSkuDetails()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Task {
                await loadSkuStats()
                if chartsViewModel.skuBreakdownAggregation != selectedPeriod.pickEntryAggregation {
                    chartsViewModel.updateSkuBreakdownAggregation(selectedPeriod.pickEntryAggregation)
                }
            }
        }
        .navigationDestination(item: $machineNavigationTarget) { target in
            MachineDetailView(machineId: target.id, session: session)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isUpdatingWeight {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Button {
                        openWeightEditor()
                    } label: {
                        Label("Update Weight", systemImage: "scalemass")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!canEditSku || sku == nil)
                    .accessibilityLabel("Update SKU weight")
                }
            }
        }
        .textFieldAlert(
            isPresented: $isShowingWeightAlert,
            text: $weightInputText,
            title: "Update Weight",
            message: weightUpdateError,
            confirmTitle: "Save",
            cancelTitle: "Cancel",
            keyboardType: .decimalPad,
            allowedCharacterSet: CharacterSet(charactersIn: "0123456789.,"),
            onConfirm: {
                Task { await submitWeightUpdate() }
            },
            onCancel: {
                weightUpdateError = nil
            }
        )
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
        isLoadingStats = true
        do {
            skuStats = try await skusService.getSkuStats(
                id: skuId,
                period: selectedPeriod,
                locationId: nil,
                machineId: nil
            )
        } catch {
            // Don't show error for stats failure, just log it
            print("Failed to load SKU stats: \(error)")
        }
        isLoadingStats = false
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

    private func openWeightEditor() {
        guard sku != nil else { return }
        weightUpdateError = nil
        weightInputText = formattedWeightInput(from: sku?.weight)
        isShowingWeightAlert = true
    }

    private func formattedWeightInput(from weight: Double?) -> String {
        guard let weight else { return "" }
        return SkuDetailView.weightFormatter.string(from: NSNumber(value: weight)) ?? "\(weight)"
    }

    private func submitWeightUpdate() async {
        if isUpdatingWeight {
            return
        }

        let trimmed = weightInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed: Double?
        if trimmed.isEmpty {
            parsed = nil
        } else {
            let normalizedText = trimmed.replacingOccurrences(of: ",", with: ".")
            let parsedNumber = SkuDetailView.weightFormatter.number(from: trimmed)?.doubleValue
                ?? Double(normalizedText)
            guard let parsedNumber else {
                await MainActor.run {
                    weightUpdateError = "Enter a valid weight."
                }
                return
            }
            if parsedNumber < 0 {
                await MainActor.run {
                    weightUpdateError = "Weight must be zero or greater."
                }
                return
            }
            parsed = parsedNumber
        }

        await MainActor.run {
            weightUpdateError = nil
            isUpdatingWeight = true
        }

        do {
            try await skusService.updateWeight(id: skuId, weight: parsed)
            await loadSkuDetails()
            await MainActor.run {
                isShowingWeightAlert = false
            }
        } catch {
            await MainActor.run {
                weightUpdateError = error.localizedDescription
            }
        }

        await MainActor.run {
            isUpdatingWeight = false
        }
    }

    private static let weightFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter
    }()
    
    private var skuDisplayTitle: String {
        if let name = sku?.name, !name.isEmpty {
            return name
        }
        if let code = sku?.code, !code.isEmpty {
            return code
        }
        return "SKU Details"
    }

    private var canViewRecentActivity: Bool {
        guard let role = resolvedRole else { return false }
        return role == .admin || role == .owner || role == .god
    }

    private var canEditSku: Bool {
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
            print("Failed to load effective role: \(error)")
        }
    }

    private func navigateToMachineDetail(_ bestMachine: SkuBestMachine) {
        guard !bestMachine.machineId.isEmpty else { return }
        machineNavigationTarget = SkuDetailMachineNavigation(id: bestMachine.machineId)
    }
}

private struct SkuDetailMachineNavigation: Identifiable, Hashable {
    let id: String
}
