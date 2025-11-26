import SwiftUI

struct SearchLocationDetailView: View {
    let locationId: String
    let session: AuthSession

    @State private var location: Location?
    @State private var locationStats: LocationStatsResponse?
    @State private var isLoading = true
    @State private var isLoadingStats = true
    @State private var locationBreakdown: PickEntryBreakdown?
    @State private var isLoadingBreakdown = true
    @State private var breakdownError: String?
    @State private var errorMessage: String?
    @State private var selectedPeriod: SkuPeriod = .week
    @State private var skuNavigationTarget: SearchLocationSkuNavigation?
    @State private var machineNavigationTarget: SearchLocationMachineNavigation?
    @State private var hasOpeningTime = false
    @State private var hasClosingTime = false
    @State private var openingTime = SearchLocationDetailView.defaultOpeningTime
    @State private var closingTime = SearchLocationDetailView.defaultClosingTime
    @State private var dwellTimeText = ""
    @State private var isSavingSchedule = false
    @State private var scheduleError: String?
    @State private var scheduleSavedAt: Date?
    @State private var showingScheduleSheet = false
    @Environment(\.openURL) private var openURL
    @AppStorage(DirectionsApp.storageKey) private var preferredDirectionsAppRawValue = DirectionsApp.appleMaps.rawValue

    private let locationsService: LocationsServicing = LocationsService()
    private let analyticsService = AnalyticsService()

    private static var defaultOpeningTime: Date {
        baseDate(hour: 8, minute: 0)
    }

    private static var defaultClosingTime: Date {
        baseDate(hour: 17, minute: 0)
    }

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
                            onMachineTap: { navigateToMachineDetail($0) },
                            hoursDisplay: hoursDisplay,
                            onConfigureHours: { showingScheduleSheet = true }
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
                    Text("Location Details")
                        .padding(.leading, 16)
                }
                .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    LocationStatsChartView(
                        breakdown: locationBreakdown,
                        isLoading: isLoadingBreakdown,
                        errorMessage: breakdownError,
                        selectedPeriod: $selectedPeriod
                    )
                } header: {
                    Text("Recent Activity")
                }
            }
        }
        .navigationTitle(locationDisplayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadLocationDetails()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Task {
                await loadLocationStats()
                await loadLocationBreakdown()
            }
        }
        .onChange(of: hasOpeningTime) { _, _ in
            resetScheduleAlerts()
        }
        .onChange(of: hasClosingTime) { _, _ in
            resetScheduleAlerts()
        }
        .onChange(of: openingTime) { _, _ in
            resetScheduleAlerts()
        }
        .onChange(of: closingTime) { _, _ in
            resetScheduleAlerts()
        }
        .onChange(of: dwellTimeText) { _, _ in
            resetScheduleAlerts()
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
        .sheet(isPresented: $showingScheduleSheet) {
            NavigationStack {
                ScrollView {
                    ConfigureHoursSheet(
                        hasOpeningTime: $hasOpeningTime,
                        hasClosingTime: $hasClosingTime,
                        openingTime: $openingTime,
                        closingTime: $closingTime,
                        dwellTimeText: $dwellTimeText,
                        isSaving: isSavingSchedule,
                        errorMessage: scheduleError,
                        lastSavedAt: scheduleSavedAt,
                        onSave: {
                            Task {
                                await saveLocationSchedule()
                            }
                        }
                    )
                    .padding()
                }
                .navigationTitle("Configure Hours")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            showingScheduleSheet = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await saveLocationSchedule()
                            }
                        } label: {
                            if isSavingSchedule {
                                ProgressView()
                            } else {
                                Text("Save")
                                    .font(.headline.weight(.semibold))
                            }
                        }
                        .disabled(isSavingSchedule)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func loadLocationDetails() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let fetchedLocation = try await locationsService.getLocation(id: locationId)
            await MainActor.run {
                location = fetchedLocation
                isLoading = false
                syncTimingState(from: fetchedLocation)
            }
            await loadLocationStats()
            await loadLocationBreakdown()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
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

    private func loadLocationBreakdown() async {
        guard location != nil else { return }
        isLoadingBreakdown = true
        breakdownError = nil

        do {
            let response = try await analyticsService.fetchPickEntryBreakdown(
                aggregation: selectedPeriod.pickEntryAggregation,
                focus: PickEntryBreakdown.ChartItemFocus(skuId: nil, machineId: nil, locationId: locationId),
                filters: PickEntryBreakdown.Filters(
                    skuIds: [],
                    machineIds: [],
                    locationIds: [locationId]
                ),
                showBars: selectedPeriod.pickEntryAggregation.defaultBars,
                credentials: session.credentials
            )
            locationBreakdown = response
        } catch let authError as AuthError {
            breakdownError = authError.localizedDescription
            locationBreakdown = nil
        } catch let analyticsError as AnalyticsServiceError {
            breakdownError = analyticsError.localizedDescription
            locationBreakdown = nil
        } catch {
            breakdownError = "We couldn't load chart data right now."
            locationBreakdown = nil
        }

        isLoadingBreakdown = false
    }

    private func saveLocationSchedule() async {
        guard let payload = await MainActor.run(body: { buildSchedulePayload() }) else {
            return
        }

        defer {
            Task { @MainActor in
                isSavingSchedule = false
            }
        }

        do {
            let updatedLocation = try await locationsService.updateLocation(
                id: payload.locationId,
                openingTimeMinutes: payload.openingMinutes,
                closingTimeMinutes: payload.closingMinutes,
                dwellTimeMinutes: payload.dwellMinutes
            )
            await MainActor.run {
                location = updatedLocation
                syncTimingState(from: updatedLocation)
                scheduleSavedAt = Date()
                showingScheduleSheet = false
            }
        } catch let authError as AuthError {
            await MainActor.run {
                scheduleError = authError.localizedDescription
            }
        } catch let locationError as LocationsServiceError {
            await MainActor.run {
                scheduleError = locationError.localizedDescription
            }
        } catch {
            await MainActor.run {
                scheduleError = "We couldn't save this location's timing details."
            }
        }
    }

    @MainActor
    private func buildSchedulePayload() -> ScheduleUpdatePayload? {
        guard let location else { return nil }

        scheduleError = nil
        scheduleSavedAt = nil

        let openingMinutes = hasOpeningTime ? minutes(from: openingTime) : nil
        let closingMinutes = hasClosingTime ? minutes(from: closingTime) : nil

        if let open = openingMinutes, let close = closingMinutes, close < open {
            scheduleError = "Closing time must be after opening time."
            return nil
        }

        switch parseDwellTimeMinutes() {
        case .failure(let validationError):
            scheduleError = validationError.localizedDescription
            return nil
        case .success(let dwellMinutes):
            isSavingSchedule = true
            return ScheduleUpdatePayload(
                locationId: location.id,
                openingMinutes: openingMinutes,
                closingMinutes: closingMinutes,
                dwellMinutes: dwellMinutes
            )
        }
    }

    @MainActor
    private func parseDwellTimeMinutes() -> Result<Int?, ScheduleValidationError> {
        let trimmed = dwellTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .success(nil)
        }

        guard let value = Int(trimmed), value >= 0, value <= 24 * 60 else {
            return .failure(.message("Dwell time must be between 0 and 1440 minutes."))
        }

        return .success(value)
    }

    @MainActor
    private func syncTimingState(from location: Location) {
        hasOpeningTime = location.openingTimeMinutes != nil
        hasClosingTime = location.closingTimeMinutes != nil
        openingTime = date(fromMinutes: location.openingTimeMinutes) ?? SearchLocationDetailView.defaultOpeningTime
        closingTime = date(fromMinutes: location.closingTimeMinutes) ?? SearchLocationDetailView.defaultClosingTime
        if let dwellMinutes = location.dwellTimeMinutes {
            dwellTimeText = "\(dwellMinutes)"
        } else {
            dwellTimeText = ""
        }
        scheduleError = nil
        scheduleSavedAt = nil
    }

    private func date(fromMinutes minutes: Int?) -> Date? {
        guard let minutes else {
            return nil
        }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .minute, value: minutes, to: startOfDay)
    }

    private func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return hour * 60 + minute
    }

    @MainActor
    private func resetScheduleAlerts() {
        scheduleError = nil
        if !isSavingSchedule {
            scheduleSavedAt = nil
        }
    }

    private static func baseDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
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

    private var hoursDisplay: HoursDisplay {
        HoursDisplay(
            opening: hasOpeningTime ? formattedTime(openingTime) : "Unspecified",
            closing: hasClosingTime ? formattedTime(closingTime) : "Unspecified",
            dwell: displayDwellText
        )
    }

    private var displayDwellText: String {
        let trimmed = dwellTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Not set"
        }
        if let value = Int(trimmed), value >= 0 {
            return "\(value) min"
        }
        return "Invalid"
    }

    private func formattedTime(_ date: Date) -> String {
        SearchLocationDetailView.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

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

private struct ScheduleUpdatePayload {
    let locationId: String
    let openingMinutes: Int?
    let closingMinutes: Int?
    let dwellMinutes: Int?
}

private enum ScheduleValidationError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(text):
            return text
        }
    }
}
