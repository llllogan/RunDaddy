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
    @State private var isUpdatingColdChestStatus = false
    @State private var isUpdatingWeight = false
    @State private var isShowingWeightAlert = false
    @State private var weightInputText = ""
    @State private var weightUpdateError: String?
    @State private var isUpdatingExpiryDays = false
    @State private var isShowingExpiryDaysAlert = false
    @State private var expiryDaysInputText = ""
    @State private var expiryDaysUpdateError: String?
    @State private var machineNavigationTarget: SkuDetailMachineNavigation?
    @State private var effectiveRole: UserRole?
    @State private var isUpdatingLabelColour = false
    @State private var selectedLabelColour: Color = .yellow
    @State private var suppressLabelColourSync = false
    @State private var desiredLabelColour: Color?
    @State private var labelColourSaveTask: Task<Void, Never>?
    @StateObject private var chartsViewModel: ChartsViewModel
    @State private var recentNotes: [Note] = []
    @State private var isLoadingNotes = false
    
    private let skusService = SkusService()
    private let authService: AuthServicing = AuthService()
    private let notesService: NotesServicing = NotesService()

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
                            isUpdatingColdChestStatus: isUpdatingColdChestStatus,
                            onToggleColdChestStatus: { toggleColdChestStatus() },
                            mostRecentPick: skuStats.mostRecentPick,
                            labelColour: $selectedLabelColour,
                            isUpdatingLabelColour: isUpdatingLabelColour,
                            canEditLabelColour: canEditSku,
                            isUpdatingExpiryDays: isUpdatingExpiryDays,
                            onConfigureExpiryDays: { openExpiryDaysEditor() }
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
                            showAggregationControls: false,
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
                                firstSeen: skuStats.firstSeen,
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
                                firstSeen: nil,
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

                if !recentNotes.isEmpty {
                    Section("Notes") {
                        ForEach(recentNotes) { note in
                            NoteRowView(note: note)
                        }

                        NavigationLink("View all notes") {
                            CompanyNotesView(
                                session: session,
                                initialFilterTag: NoteTagOption(
                                    id: skuId,
                                    type: .sku,
                                    label: sku.code,
                                    subtitle: sku.name
                                )
                            )
                        }
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
            await loadRecentNotes()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Task {
                await loadSkuStats()
                if chartsViewModel.skuBreakdownAggregation != selectedPeriod.pickEntryAggregation {
                    chartsViewModel.updateSkuBreakdownAggregation(selectedPeriod.pickEntryAggregation)
                }
            }
        }
        .onChange(of: selectedLabelColour) { _, newValue in
            guard sku?.isFreshOrFrozen == true, canEditSku, !suppressLabelColourSync else { return }
            queueLabelColourSave(newValue)
        }
        .navigationDestination(item: $machineNavigationTarget) { target in
            MachineDetailView(machineId: target.id, session: session)
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
        .textFieldAlert(
            isPresented: $isShowingExpiryDaysAlert,
            text: $expiryDaysInputText,
            title: "Expiry Days",
            message: expiryDaysUpdateError,
            confirmTitle: "Save",
            cancelTitle: "Cancel",
            keyboardType: .numberPad,
            allowedCharacterSet: CharacterSet.decimalDigits,
            onConfirm: {
                Task { await submitExpiryDaysUpdate() }
            },
            onCancel: {
                expiryDaysUpdateError = nil
            }
        )
    }
    
    private func loadSkuDetails(shouldRefreshStats: Bool = true) async {
        do {
            let fetchedSku = try await skusService.getSku(id: skuId)
            await MainActor.run {
                sku = fetchedSku
                isLoading = false
                syncLabelColourState(with: fetchedSku)
            }

            if shouldRefreshStats {
                await loadSkuStats()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func loadSkuStats() async {
        await MainActor.run {
            isLoadingStats = true
        }
        do {
            let stats = try await skusService.getSkuStats(
                id: skuId,
                period: selectedPeriod,
                locationId: nil,
                machineId: nil
            )
            await MainActor.run {
                skuStats = stats
            }
        } catch {
            // Don't show error for stats failure, just log it
            print("Failed to load SKU stats: \(error)")
        }
        await MainActor.run {
            isLoadingStats = false
        }
    }

    private func loadRecentNotes() async {
        if isLoadingNotes {
            return
        }

        isLoadingNotes = true
        defer { isLoadingNotes = false }

        do {
            let response = try await notesService.fetchNotes(
                targetType: .sku,
                targetId: skuId,
                limit: 5,
                offset: nil,
                credentials: session.credentials
            )
            recentNotes = Array(response.notes.prefix(5))
        } catch {
            recentNotes = []
        }
    }

    private func toggleColdChestStatus() {
        guard let sku = sku else { return }
        
        isUpdatingColdChestStatus = true
        Task {
            do {
                try await skusService.updateColdChestStatus(
                    id: sku.id,
                    isFreshOrFrozen: !sku.isFreshOrFrozen
                )
                
                // Refresh SKU details to get updated status
                await loadSkuDetails()
            } catch {
                // Could show error alert here
                print("Failed to update cold chest status: \(error)")
            }
            isUpdatingColdChestStatus = false
        }
    }

    @MainActor
    private func queueLabelColourSave(_ color: Color) {
        desiredLabelColour = color
        if labelColourSaveTask == nil {
            labelColourSaveTask = Task { await runLabelColourSaveLoop() }
        }
    }

    private func runLabelColourSaveLoop() async {
        while true {
            let nextColour = await MainActor.run { () -> Color? in
                let next = desiredLabelColour
                desiredLabelColour = nil
                return next
            }

            guard let nextColour else {
                await MainActor.run { labelColourSaveTask = nil }
                return
            }

            await MainActor.run { isUpdatingLabelColour = true }
            let hexString = ColorCodec.hexString(from: nextColour)

            do {
                try await skusService.updateLabelColour(id: skuId, labelColourHex: hexString)
                await MainActor.run {
                    updateLocalSkuLabelColour(hexString)
                }
            } catch {
                print("Failed to update label colour: \(error)")
                await loadSkuDetails(shouldRefreshStats: false)
            }

            await MainActor.run { isUpdatingLabelColour = false }
        }
    }

    private func updateLocalSkuLabelColour(_ hexString: String?) {
        suppressLabelColourSync = true

        if let currentSku = sku {
            sku = SKU(
                id: currentSku.id,
                code: currentSku.code,
                name: currentSku.name,
                type: currentSku.type,
                category: currentSku.category,
                weight: currentSku.weight,
                labelColour: hexString,
                countNeededPointer: currentSku.countNeededPointer,
                isFreshOrFrozen: currentSku.isFreshOrFrozen,
                expiryDays: currentSku.expiryDays
            )
        }

        suppressLabelColourSync = false
    }

    private func syncLabelColourState(with sku: SKU) {
        suppressLabelColourSync = true
        if let colour = ColorCodec.color(fromHex: sku.labelColour) {
            selectedLabelColour = colour
        } else {
            selectedLabelColour = .yellow
        }
        suppressLabelColourSync = false
    }

    private func openWeightEditor() {
        guard sku != nil else { return }
        weightUpdateError = nil
        weightInputText = formattedWeightInput(from: sku?.weight)
        isShowingWeightAlert = true
    }

    private func openExpiryDaysEditor() {
        guard canEditSku else { return }
        guard let sku else { return }

        expiryDaysUpdateError = nil
        let current = sku.expiryDays ?? 0
        expiryDaysInputText = current > 0 ? "\(current)" : ""
        isShowingExpiryDaysAlert = true
    }

    private func formattedWeightInput(from weight: Double?) -> String {
        guard let weight else { return "" }
        return SkuDetailView.weightFormatter.string(from: NSNumber(value: weight)) ?? "\(weight)"
    }

    private func submitExpiryDaysUpdate() async {
        guard canEditSku else { return }
        guard let sku else { return }
        if isUpdatingExpiryDays {
            return
        }

        let trimmed = expiryDaysInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed: Int
        if trimmed.isEmpty {
            parsed = 0
        } else if let value = Int(trimmed), value >= 0 {
            parsed = value
        } else {
            await MainActor.run {
                expiryDaysUpdateError = "Enter a non-negative whole number."
                isShowingExpiryDaysAlert = true
            }
            return
        }

        await MainActor.run {
            expiryDaysUpdateError = nil
            isUpdatingExpiryDays = true
        }

        do {
            try await skusService.updateExpiryDays(id: sku.id, expiryDays: parsed)
            await loadSkuDetails(shouldRefreshStats: false)
        } catch {
            await MainActor.run {
                expiryDaysUpdateError = error.localizedDescription
                isShowingExpiryDaysAlert = true
            }
        }

        await MainActor.run {
            isUpdatingExpiryDays = false
        }
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
            await loadSkuDetails(shouldRefreshStats: false)
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
