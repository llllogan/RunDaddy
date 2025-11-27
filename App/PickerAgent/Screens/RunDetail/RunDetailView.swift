//
//  RunDetailView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/25/2025.
//

import SwiftUI
import MapKit

struct RunDetailView: View {
    @StateObject private var viewModel: RunDetailViewModel
    @State private var showingPackingSession = false
    @State private var packingSessionId: String?
    @State private var isCreatingPackingSession = false
    @State private var showingCategorySheet = false
    @State private var selectedCategoryIds: Set<String> = []
    @State private var isCheckingCompanyTier = false
    @State private var showingLocationOrderSheet = false
    @State private var showingPendingEntries = false
    @State private var isResettingRunPickStatuses = false
    @State private var confirmingRunReset = false
    @State private var locationPendingDeletion: RunLocationSection?
    @State private var deletingLocationIDs: Set<String> = []
    @State private var notifications: [InAppNotification] = []
    
    // Check if run is 100% complete
    private var isRunComplete: Bool {
        guard let detail = viewModel.detail else { return false }
        let totalCoils = detail.pickItems.count
        guard totalCoils > 0 else { return false }
        
        let packedCoils = detail.pickItems.reduce(into: 0) { partialResult, item in
            if item.isPicked {
                partialResult += 1
            }
        }
        
        return packedCoils >= totalCoils
    }
    @Environment(\.openURL) private var openURL
    @AppStorage(DirectionsApp.storageKey) private var preferredDirectionsAppRawValue = DirectionsApp.appleMaps.rawValue

    @MainActor
    init(runId: String, session: AuthSession, service: RunsServicing? = nil) {
        let resolvedService = service ?? RunsService()
        _viewModel = StateObject(wrappedValue: RunDetailViewModel(runId: runId, session: session, service: resolvedService))
    }

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.overview == nil {
                Section {
                    LoadingRow()
                }
            } else {
                if let overview = viewModel.overview {
                    Section {
                        RunOverviewBento(
                            summary: overview,
                            viewModel: viewModel,
                            pendingItemsTap: {
                                showingPendingEntries = true
                            }
                        )
                            .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } header: {
                        Text("Run Overview")
                    }
                }

                Section("Locations") {
                    if viewModel.locationSections.isEmpty {
                        Text("No locations are assigned to this run yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(viewModel.locationSections) { section in
                            locationRow(for: section)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Run Details")
        .navigationBarTitleDisplayMode(.inline)
        .inAppNotifications(notifications, onDismiss: { notification in
            notifications.removeAll { $0.id == notification.id }
        })
        .navigationDestination(isPresented: $showingPendingEntries) {
            PendingPickEntriesView(
                viewModel: viewModel,
                runId: viewModel.detail?.id ?? viewModel.runId,
                session: viewModel.session,
                service: viewModel.service
            )
        }
        .task {
            await viewModel.load()
            await viewModel.loadActivePackingSession()
            
            // Check if run is 100% complete and update status to READY
            if isRunComplete && viewModel.detail?.status != "READY" {
                await viewModel.updateRunStatus(to: "READY")
            }
        }
        .refreshable {
            await viewModel.load(force: true)
            await viewModel.loadActivePackingSession()
            
            // Check if run is 100% complete and update status to READY
            if isRunComplete && viewModel.detail?.status != "READY" {
                await viewModel.updateRunStatus(to: "READY")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isResettingRunPickStatuses {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Button {
                        confirmingRunReset = true
                    } label: {
                        Label("Reset Packed Status", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!canResetRunPickStatuses)
                    .accessibilityLabel("Reset packed status for all picks")
                }

                Menu {
                    if locationMenuOptions.isEmpty {
                        Text("No locations available")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(locationMenuOptions) { option in
                            Button {
                                openLocationInMaps(option)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title)
                                    if let subtitle = option.address {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Label("Locations", systemImage: "map")
                }
                .disabled(locationMenuOptions.isEmpty)

                Button {
                    showingLocationOrderSheet = true
                } label: {
                    Label("Reorder", systemImage: "list.number")
                }
                .disabled(viewModel.locationSections.count < 2)
            }
            
            ToolbarItem(placement: .bottomBar) {
                let hasActiveSession = viewModel.activePackingSessionId != nil
                
                // Check if run is 100% complete
                let isRunComplete = {
                    guard let detail = viewModel.detail else { return false }
                    let totalCoils = detail.pickItems.count
                    guard totalCoils > 0 else { return false }
                    
                    let packedCoils = detail.pickItems.reduce(into: 0) { partialResult, item in
                        if item.isPicked {
                            partialResult += 1
                        }
                    }
                    
                    return packedCoils >= totalCoils
                }()
                
                Button(hasActiveSession ? "Resume Packing" : "Start Packing", systemImage: hasActiveSession ? "playpause" : "play") {
                    if let activeId = viewModel.activePackingSessionId {
                        packingSessionId = activeId
                        showingPackingSession = true
                    } else {
                        Task {
                            await handleStartPackingTapped()
                        }
                    }
                }
                .labelStyle(.titleOnly)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isCreatingPackingSession || isRunComplete || isCheckingCompanyTier)
                .fullScreenCover(isPresented: $showingPackingSession, onDismiss: {
                    packingSessionId = nil
                    Task {
                        await viewModel.load(force: true)
                        await viewModel.loadActivePackingSession()
                    }
                }) {
                    let resolvedPackingSessionId = packingSessionId ?? viewModel.activePackingSessionId
                    if let resolvedPackingSessionId {
                        PackingSessionSheet(
                            runId: viewModel.detail?.id ?? viewModel.runId,
                            packingSessionId: resolvedPackingSessionId,
                            session: viewModel.session,
                            onAbandon: {
                                viewModel.activePackingSessionId = nil
                            },
                            onPause: {
                                viewModel.activePackingSessionId = resolvedPackingSessionId
                                packingSessionId = resolvedPackingSessionId
                            }
                        )
                    } else {
                        ProgressView("Starting packing session...")
                    }
                }
            }
        }
        .sheet(isPresented: $showingCategorySheet) {
            PackingCategorySelectionSheet(
                categories: categoryOptions,
                selectedCategoryIds: $selectedCategoryIds,
                isStarting: isCreatingPackingSession,
                onCancel: {
                    showingCategorySheet = false
                },
                onStart: {
                    Task {
                        let payload = payloadCategories(from: selectedCategoryIds)
                        await startPackingSession(selectedCategories: payload)
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(isCreatingPackingSession)
        }
        .sheet(isPresented: $showingLocationOrderSheet) {
            ReorderLocationsSheet(
                viewModel: viewModel,
                sections: viewModel.locationSections
            )
        }
        .alert(item: $locationPendingDeletion) { section in
            Alert(
                title: Text("Delete picks at \(section.title)?"),
                message: Text(locationDeletionMessage(for: section)),
                primaryButton: .destructive(Text("Delete")) {
                    locationPendingDeletion = nil
                    Task {
                        await deleteLocationPickEntries(for: section)
                    }
                },
                secondaryButton: .cancel {
                    locationPendingDeletion = nil
                }
            )
        }
        .alert("Reset Packed Status?", isPresented: $confirmingRunReset) {
            Button("Reset", role: .destructive) {
                Task {
                    await resetRunPickStatuses()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will mark every packed pick entry in this run as pending.")
        }
        .sensoryFeedback(.warning, trigger: viewModel.resetTrigger)
    }
}

private extension RunDetailView {
    var preferredDirectionsApp: DirectionsApp {
        DirectionsApp(rawValue: preferredDirectionsAppRawValue) ?? .appleMaps
    }
    
    var categoryOptions: [SkuCategoryOption] {
        var options: [SkuCategoryOption] = []
        var seen = Set<String>()
        let pendingItems = viewModel.pendingUnassignedPickItems
        
        guard !pendingItems.isEmpty else { return [] }
        
        for pickItem in pendingItems {
            let rawCategory = pickItem.sku?.category?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedCategory = (rawCategory?.isEmpty ?? true) ? nil : rawCategory
            let key = normalizedCategory?.lowercased() ?? uncategorizedCategoryKey
            
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            
            let label = normalizedCategory ?? "Uncategorized"
            options.append(SkuCategoryOption(id: key, value: normalizedCategory, label: label))
        }
        
        return options.sorted { first, second in
            first.label.localizedCaseInsensitiveCompare(second.label) == .orderedAscending
        }
    }
    
    var uncategorizedCategoryKey: String {
        "_uncategorized_category"
    }

    var canResetRunPickStatuses: Bool {
        guard let pickItems = viewModel.detail?.pickItems else {
            return false
        }
        return pickItems.contains(where: { $0.isPicked })
    }

    @MainActor
    func handleStartPackingTapped() async {
        guard !isCreatingPackingSession, !isCheckingCompanyTier else { return }
        isCheckingCompanyTier = true
        defer { isCheckingCompanyTier = false }

        guard let canBreakDownRun = await viewModel.resolveCanBreakDownRun() else {
            return
        }

        if canBreakDownRun {
            selectedCategoryIds = Set(categoryOptions.map(\.id))
            showingCategorySheet = true
            return
        }

        await startPackingSession(selectedCategories: nil)
    }
    
    func payloadCategories(from selection: Set<String>) -> [String?]? {
        guard !selection.isEmpty else { return nil }
        
        let lookup = Dictionary(uniqueKeysWithValues: categoryOptions.map { ($0.id, $0.value) })
        var includeUncategorized = false
        var normalized = Set<String>()
        
        selection.forEach { id in
            if id == uncategorizedCategoryKey {
                includeUncategorized = true
                return
            }
            guard let rawValue = lookup[id] else { return }
            let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                normalized.insert(trimmed)
            } else {
                includeUncategorized = true
            }
        }
        
        var payload = normalized.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { Optional($0) }
        if includeUncategorized {
            payload.append(nil)
        }
        return payload
    }
    
    func pendingItems(for categories: [String?]?) -> [RunDetail.PickItem] {
        let categoryKeys = normalizedCategoryKeys(from: categories)
        guard !categoryKeys.isEmpty else {
            return viewModel.pendingUnassignedPickItems
        }
        
        return viewModel.pendingUnassignedPickItems.filter { item in
            let key = normalizedCategoryKey(for: item.sku?.category)
            return categoryKeys.contains(key)
        }
    }
    
    private func normalizedCategoryKeys(from categories: [String?]?) -> Set<String> {
        guard let categories, !categories.isEmpty else { return [] }

        return Set(categories.map { normalizedCategoryKey(for: $0) })
    }
    
    private func normalizedCategoryKey(for category: String?) -> String {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return uncategorizedCategoryKey }
        return trimmed.lowercased()
    }
    
    func normalizedCategoriesPayload(from categories: [String?]?) -> [String?]? {
        guard let categories, !categories.isEmpty else { return nil }
        
        var includeUncategorized = false
        var normalized = Set<String>()
        
        categories.forEach { category in
            let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                normalized.insert(trimmed)
            } else {
                includeUncategorized = true
            }
        }
        
        var payload = normalized.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { Optional($0) }
        if includeUncategorized {
            payload.append(nil)
        }
        return payload
    }

    var locationMenuOptions: [LocationMenuOption] {
        viewModel.locationSections.compactMap { section in
            guard let location = section.location else { return nil }
            let trimmedAddress = location.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let address = trimmedAddress.isEmpty ? nil : trimmedAddress
            let querySource = address ?? section.title
            return LocationMenuOption(
                id: section.id,
                title: section.title,
                address: address,
                query: querySource
            )
        }
    }

    func openLocationInMaps(_ option: LocationMenuOption) {
        let directionsApp = preferredDirectionsApp
        guard let targetURL = directionsApp.url(for: option.query) else { return }

        openURL(targetURL) { accepted in
            guard !accepted, directionsApp == .waze, let fallbackURL = DirectionsApp.appleMaps.url(for: option.query) else {
                return
            }
            openURL(fallbackURL)
        }
    }
    
    @MainActor
    func startPackingSession(selectedCategories: [String?]? = nil) async {
        guard !isCreatingPackingSession else { return }
        isCreatingPackingSession = true
        defer { isCreatingPackingSession = false }

        // Check if run is already 100% complete
        if isRunComplete {
            viewModel.errorMessage = "This run is already complete and cannot start a new packing session."
            return
        }

        let normalizedCategories = normalizedCategoriesPayload(from: selectedCategories)
        let pendingItems = pendingItems(for: normalizedCategories)
        
        guard !pendingItems.isEmpty else {
            if normalizedCategories == nil {
                viewModel.errorMessage = "No pending pick entries are available to start a packing session."
                return
            }
            
            viewModel.errorMessage = "No pending pick entries are available in the selected categories."
            return
        }

        do {
            let packingSession = try await viewModel.startPackingSession(categories: normalizedCategories)
            packingSessionId = packingSession.id
            showingCategorySheet = false
            showingPackingSession = true
        } catch {
            if let authError = error as? AuthError {
                viewModel.errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                viewModel.errorMessage = runError.localizedDescription
            } else {
                viewModel.errorMessage = "We couldn't start a packing session. Please try again."
            }
        }
    }

    @MainActor
    func resetRunPickStatuses() async {
        guard !isResettingRunPickStatuses else { return }
        isResettingRunPickStatuses = true
        defer { isResettingRunPickStatuses = false }

        let pickItems = viewModel.detail?.pickItems ?? []
        _ = await viewModel.resetPickStatuses(for: pickItems)
    }

    private func locationDeletionMessage(for section: RunLocationSection) -> String {
        let pickCount = viewModel.pickItemCount(for: section.id)
        if pickCount == 0 {
            return "There are no pick entries to delete for this location."
        }

        let entryLabel = pickCount == 1 ? "pick entry" : "pick entries"
        return "This will permanently delete \(pickCount) \(entryLabel) for this location in this run."
    }

    @MainActor
    private func deleteLocationPickEntries(for section: RunLocationSection) async {
        guard !deletingLocationIDs.contains(section.id) else { return }
        deletingLocationIDs.insert(section.id)
        defer { deletingLocationIDs.remove(section.id) }

        _ = await viewModel.deletePickEntries(for: section.id)
    }

    private func chocolateBoxDisplay(for section: RunLocationSection) -> String? {
        let targetLocationId = section.location?.id ?? RunLocationSection.unassignedIdentifier

        let matchingBoxes = viewModel.chocolateBoxes.filter { box in
            guard let locationId = box.machine?.location?.id else {
                return targetLocationId == RunLocationSection.unassignedIdentifier
            }
            return locationId == targetLocationId
        }

        guard !matchingBoxes.isEmpty else {
            return nil
        }

        let numbers = matchingBoxes.map(\.number).sorted()
        let display = numbers.prefix(3).map(String.init).joined(separator: ", ")

        if numbers.count > 3 {
            return "\(display)..."
        }

        return display
    }

    @ViewBuilder
    private func locationRow(for section: RunLocationSection) -> some View {
        let isDeleting = deletingLocationIDs.contains(section.id)
        let pickCount = viewModel.pickItemCount(for: section.id)
        let chocolateBoxesLabel = chocolateBoxDisplay(for: section)
        let locationDetail = viewModel.locationDetail(for: section.id)
        let machines = locationDetail?.machines ?? []

        Group {
            if let locationDetail {
                NavigationLink {
                    LocationDetailView(
                        detail: locationDetail,
                        runId: viewModel.detail?.id ?? "",
                        session: viewModel.session,
                        service: viewModel.service,
                        viewModel: viewModel,
                        onPickStatusChanged: {
                            await viewModel.load(force: true)
                        }
                    )
                } label: {
                    LocationSummaryRow(
                        section: section,
                        machines: machines,
                        chocolateBoxLabel: chocolateBoxesLabel,
                        isProcessing: isDeleting
                    )
                }
                .disabled(isDeleting)
            } else {
                LocationSummaryRow(
                    section: section,
                    machines: machines,
                    chocolateBoxLabel: chocolateBoxesLabel,
                    isProcessing: isDeleting
                )
            }
        }
        .opacity(isDeleting ? 0.45 : 1)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: pickCount > 0) {
            Button(role: .destructive) {
                locationPendingDeletion = section
            } label: {
                Label("Delete Location", systemImage: "trash")
            }
            .disabled(isDeleting || pickCount == 0)
        }
    }
}

private struct SkuCategoryOption: Identifiable, Hashable {
    let id: String
    let value: String?
    let label: String
}

private struct LocationMenuOption: Identifiable, Equatable {
    let id: String
    let title: String
    let address: String?
    let query: String
}

private struct LocationSummaryRow: View {
    let section: RunLocationSection
    var machines: [RunDetail.Machine] = []
    var chocolateBoxLabel: String? = nil
    var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)
                .fontWeight(.semibold)

            if let subtitle = section.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            FlowLayout(spacing: 6) {
                ForEach(machineTypeChips) { chip in
                    InfoChip(
                        title: nil,
                        date: nil,
                        text: chip.label,
                        colour: Color.indigo.opacity(0.15),
                        foregroundColour: Color.indigo,
                        icon: nil
                    )
                }

                if section.remainingCoils > 0 {
                    InfoChip(title: nil, date: nil, text: "\(section.remainingCoils) remaining", colour: nil, foregroundColour: nil, icon: nil)
                } else {
                    InfoChip(title: nil, date: nil, text: "All Packed", colour: .green.opacity(0.15), foregroundColour: .green, icon: nil)
                }

                if let chocolateBoxLabel {
                    InfoChip(
                        title: nil,
                        date: nil,
                        text: chocolateBoxLabel,
                        colour: Color.brown.opacity(0.15),
                        foregroundColour: Color.brown,
                        icon: "shippingbox"
                    )
                }
            }
            .accessibilityElement(children: .combine)

            if isProcessing {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var machineTypeChips: [MachineTypeChip] {
        machines.compactMap { machine in
            let trimmedDescription = machine.machineType?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let typeDescription = (trimmedDescription?.isEmpty == false) ? trimmedDescription : nil
            let fallbackName = machine.machineType?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = typeDescription ?? (fallbackName?.isEmpty == false ? fallbackName : "Unknown machine type")

            guard let label else { return nil }
            return MachineTypeChip(id: machine.id, label: label)
        }
    }

    private struct MachineTypeChip: Identifiable {
        let id: String
        let label: String
    }
}

private struct LoadingRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading run…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ErrorRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct PackingCategorySelectionSheet: View {
    let categories: [SkuCategoryOption]
    @Binding var selectedCategoryIds: Set<String>
    let isStarting: Bool
    let onCancel: () -> Void
    let onStart: () -> Void
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if categories.isEmpty {
                        Text("No SKU categories found for this run.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(categories) { category in
                            CategorySelectionRow(
                                category: category,
                                isSelected: selectedCategoryIds.contains(category.id),
                                onToggle: {
                                    toggle(category)
                                }
                            )
                        }
                    }
                } header: {
                    Text("Choose Categories")
                } footer: {
                    Text("Only picks in the selected categories will be added to this packing session.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Start Packing")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isStarting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isStarting)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onStart()
                    }
                    .disabled(isStarting || (!categories.isEmpty && selectedCategoryIds.isEmpty))
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    private func toggle(_ category: SkuCategoryOption) {
        if selectedCategoryIds.contains(category.id) {
            selectedCategoryIds.remove(category.id)
        } else {
            selectedCategoryIds.insert(category.id)
        }
    }
}

private struct CategorySelectionRow: View {
    let category: SkuCategoryOption
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.label)
                        .font(.headline)
                        .foregroundStyle(Color(.label))
                    
                    Text("Include this category")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .secondary)
                    .font(.title2)
            }
        }
    }
}

private struct ReorderLocationsSheet: View {
    @ObservedObject var viewModel: RunDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftSections: [RunLocationSection]
    @State private var isSaving = false
    @State private var isOptimizing = false
    @State private var isCalculatingTravel = false
    @State private var errorMessage: String?
    @State private var startTime: Date
    @State private var inboundLegs: [String: RouteLeg] = [:]
    @State private var totalTravelSeconds: TimeInterval?
    private let directionsClient = RateLimitedDirections()
    @State private var didHitMapSearchThrottle = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var routePreviewAnnotations: [RouteAnnotation] = []
    @State private var routePolyline: [CLLocationCoordinate2D] = []
    @State private var showingShopEditor = false
    @StateObject private var companyLocationPickerViewModel = ProfileViewModel(
        authService: AuthService(),
        inviteCodesService: InviteCodesService()
    )
    @State private var notifications: [InAppNotification] = []
    private let startTimeStore = RouteStartTimeStore()

    init(viewModel: RunDetailViewModel, sections: [RunLocationSection]) {
        self.viewModel = viewModel
        _draftSections = State(initialValue: sections)
        let initialStart = startTimeStore.load(for: viewModel.runId) ?? Date()
        _startTime = State(initialValue: initialStart)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if draftSections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "mappin")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No locations to reorder yet.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        setupSection
                        routePreviewSection
                        Section(footer: footer) {
                            ForEach(Array(draftSections.enumerated()), id: \.1.id) { index, section in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(section.title)
                                            .font(.body.weight(.semibold))
                                    }

                                    if let leg = inboundLegs[section.id] {
                                        HStack(spacing: 2) {
                                            Image(systemName: "car.fill")
                                            Text("\(travelDisplay(leg.etaSeconds)) from \(isFirst(index) ? "Shop" : leg.fromLabel)")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }

                                    if let subtitle = section.subtitle {
                                        Text(subtitle)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .onMove { indices, newOffset in
                                draftSections.move(fromOffsets: indices, toOffset: newOffset)
                                Task {
                                    await refreshTravelEstimates()
                                }
                            }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                    .disabled(isSaving)
                }

            }
            .navigationTitle("Reorder Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await persistChanges()
                        }
                    }
                    .disabled(isSaving || draftSections.count < 2)
                }

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task {
                            await runOptimisation()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isOptimizing || isCalculatingTravel {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            Text(optimiseLabel)
                        }
                    }
                    .disabled(isSaving || isOptimizing || isCalculatingTravel || draftSections.count < 2)
                }
            }
        }
        .task {
            await refreshTravelEstimates()
        }
        .inAppNotifications(notifications, onDismiss: { notification in
            notifications.removeAll { $0.id == notification.id }
        })
        .sheet(isPresented: $showingShopEditor) {
            if let company = companyForEditor {
                NavigationStack {
                    CompanyLocationPickerView(
                        viewModel: companyLocationPickerViewModel,
                        company: company,
                        showsCancel: true
                    )
                    .onDisappear {
                        Task {
                            await viewModel.load(force: true)
                            await refreshTravelEstimates()
                        }
                    }
                }
            } else {
                Text("Company details unavailable.")
                    .font(.body)
                    .padding()
            }
        }
    }

    private func pushErrorBanner(_ message: String) {
        let notification = InAppNotification(message: message, style: .error)
        notifications.append(notification)
    }

    private var setupSection: some View {
        Section("Run Setup") {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shop")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(companyLocationLabel)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                Spacer()
                if canEditShopLocation, companyForEditor != nil {
                    Button {
                        prepareShopEditor()
                        showingShopEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Edit shop address")
                }
            }

            DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .onChange(of: startTime) { _, _ in
                    startTimeStore.save(startTime, for: viewModel.runId)
                    Task {
                        await refreshTravelEstimates()
                    }
                }
        }
    }

    private var routePreviewSection: some View {
        Section("Route Preview") {
            if routePreviewAnnotations.isEmpty {
                Text(routePreviewPlaceholder)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                Map(position: $mapCameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
                    if routePolyline.count >= 2 {
                        MapPolyline(coordinates: routePolyline)
                            .stroke(.blue.opacity(0.6), lineWidth: 4)
                    }
                    
                    ForEach(routePreviewAnnotations) { annotation in
                        mapAnnotationContent(for: annotation)
                    }
                }
                .frame(height: 260)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
//                .clipShape(RoundedRectangle(cornerRadius: 12))
                .listRowSeparator(.hidden)
                
                HStack {
                    Text("Shop → Shop")
                    Spacer()
                    Text(travelDisplay(totalTravelSeconds))
                        .font(.body.weight(.semibold))
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .padding(.vertical, 16)
                .padding(.horizontal, 18)
                .background(Color(.systemBackground))
                .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 12, bottomTrailing: 12, topTrailing: 0)))
            }
        }
    }

    private var routePreviewPlaceholder: String {
        if companyStartAddress == nil {
            return "Add a shop address to preview the route."
        }
        if draftSections.isEmpty {
            return "Add locations to preview the route."
        }
        return "We couldn't plot these stops yet. Confirm the addresses look correct."
    }

    @MapContentBuilder
    private func mapAnnotationContent(for annotation: RouteAnnotation) -> some MapContent {
        let pinColor: Color = {
            switch annotation.kind {
            case .shop:
                return Color.green.opacity(0.9)
            case .stop:
                return Color.blue.opacity(0.9)
            }
        }()

        switch annotation.kind {
        case .shop:
            Marker("", systemImage: "building.2.fill", coordinate: annotation.coordinate)
                .tint(pinColor)
                .annotationTitles(.hidden)
        case .stop(let order):
            Marker("", systemImage: numberSymbolName(for: order), coordinate: annotation.coordinate)
                .tint(pinColor)
                .annotationTitles(.hidden)
        }
    }

    private func numberSymbolName(for order: Int) -> String {
        if (0...50).contains(order) {
            return "\(order).circle.fill"
        }
        return "circle.fill"
    }

    private var footer: some View {
        Text("Locations are in run order, packing announcements will be in reverse order.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }

    private var canEditShopLocation: Bool {
        guard let role = viewModel.session.profile.role?.uppercased() else { return false }
        return role == "OWNER" || role == "ADMIN" || role == "GOD"
    }

    private var companyForEditor: CompanyInfo? {
        guard let companyId = viewModel.detail?.companyId else { return nil }
        let role = viewModel.session.profile.role ?? "PICKER"
        return CompanyInfo(
            id: companyId,
            name: "Company",
            role: role,
            location: viewModel.companyLocation,
            timeZone: nil
        )
    }

    private func prepareShopEditor() {
        guard let company = companyForEditor else { return }
        companyLocationPickerViewModel.currentCompany = company
        companyLocationPickerViewModel.companyLocationAddress = viewModel.companyLocation ?? ""
    }

    private func persistChanges() async {
        guard draftSections.count >= 1 else {
            dismiss()
            return
        }

        isSaving = true
        errorMessage = nil

        let sectionsSnapshot = draftSections
        let orderedLocationIds: [String?] = sectionsSnapshot.map { section in
            locationIdentifier(for: section)
        }
        do {
            try await viewModel.saveLocationOrder(with: orderedLocationIds)
            dismiss()
        } catch {
            pushErrorBanner(error.localizedDescription)
        }

        isSaving = false
    }

    private func locationIdentifier(for section: RunLocationSection) -> String? {
        if let locationId = section.location?.id, !locationId.isEmpty {
            return locationId
        }
        if section.id == RunLocationSection.unassignedIdentifier || section.id.isEmpty {
            return nil
        }
        return section.id
    }

    private var companyLocationLabel: String {
        if let location = viewModel.companyLocation?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            return location
        }
        return "Please configure a company location"
    }

    private struct RouteNode: Identifiable, Equatable {
        let id: String
        let section: RunLocationSection
        let address: String
        let mapItem: MKMapItem
        let schedule: ResolvedSchedule
    }

    private struct ResolvedSchedule: Equatable {
        private static let defaultOpeningMinutes = 0
        private static let defaultClosingMinutes = (24 * 60) - 1
        private static let defaultDwellMinutes = 20

        let openingMinutes: Int
        let closingMinutes: Int
        let dwellMinutes: Int

        init(openingMinutes: Int?, closingMinutes: Int?, dwellMinutes: Int?) {
            let resolvedOpen = openingMinutes ?? Self.defaultOpeningMinutes
            let clampedOpen = max(0, min(resolvedOpen, Self.defaultClosingMinutes))

            let resolvedClose = closingMinutes ?? Self.defaultClosingMinutes
            let minimumClose = clampedOpen + 1
            let clampedClose = max(minimumClose, min(resolvedClose, Self.defaultClosingMinutes))

            let resolvedDwell = dwellMinutes ?? Self.defaultDwellMinutes

            self.openingMinutes = clampedOpen
            self.closingMinutes = clampedClose
            self.dwellMinutes = max(1, resolvedDwell)
        }

        var dwellSeconds: TimeInterval {
            TimeInterval(dwellMinutes * 60)
        }

        func window(for date: Date, calendar: Calendar = .current) -> (open: Date, close: Date)? {
            var openComponents = calendar.dateComponents([.year, .month, .day], from: date)
            openComponents.hour = openingMinutes / 60
            openComponents.minute = openingMinutes % 60

            var closeComponents = calendar.dateComponents([.year, .month, .day], from: date)
            closeComponents.hour = closingMinutes / 60
            closeComponents.minute = closingMinutes % 60

            guard let openDate = calendar.date(from: openComponents),
                  let closeDate = calendar.date(from: closeComponents) else {
                return nil
            }
            return (open: openDate, close: closeDate)
        }
    }
    
    private struct RouteAnnotation: Identifiable {
        enum Kind {
            case shop
            case stop(order: Int)
        }
        
        let id: String
        let title: String
        let subtitle: String?
        let coordinate: CLLocationCoordinate2D
        let kind: Kind
        
        var isShop: Bool {
            if case .shop = kind { return true }
            return false
        }
    }

    private func runOptimisation() async {
        guard draftSections.count >= 2 else { return }

        await MainActor.run {
            isOptimizing = true
            errorMessage = nil
        }
        defer {
            Task { @MainActor in
                isOptimizing = false
            }
        }

        guard let companyAddress = companyStartAddress else {
            await MainActor.run {
                pushErrorBanner("Add a shop address to optimise the route.")
            }
            return
        }

        guard let originItem = await mapItem(for: companyAddress) else {
            await MainActor.run {
                if didHitMapSearchThrottle {
                    pushErrorBanner("Maps lookups are temporarily rate limited. Please try again in a moment.")
                } else {
                    pushErrorBanner("We couldn't locate the shop address in Maps.")
                }
            }
            return
        }

        let (stops, unresolved, unassigned) = await buildRouteNodes()
        guard !stops.isEmpty else {
            await MainActor.run {
                pushErrorBanner("We couldn't resolve any locations for optimisation.")
            }
            return
        }

        let orderedNodes = await computeOptimisedSections(origin: originItem, stops: stops)

        await MainActor.run {
            withAnimation {
                draftSections = orderedNodes.map(\.section) + unresolved + unassigned
            }
            if orderedNodes.isEmpty {
                pushErrorBanner("We couldn't create a route between these stops.")
            }
            Task {
                await refreshTravelEstimates()
            }
        }
    }

    private func computeOptimisedSections(origin: MKMapItem, stops: [RouteNode]) async -> [RouteNode] {
        var currentItem = origin
        var currentTime = startTime
        var remaining = stops
        var ordered: [RouteNode] = []

        while !remaining.isEmpty {
            guard let next = await nextStop(
                from: currentItem,
                currentTime: currentTime,
                remaining: remaining,
                origin: origin
            ) else {
                break
            }

            ordered.append(next.node)
            currentItem = next.node.mapItem
            currentTime = next.finishTime
            remaining.removeAll { $0.id == next.node.id }
        }

        return ordered + remaining
    }

    private func nextStop(
        from current: MKMapItem,
        currentTime: Date,
        remaining: [RouteNode],
        origin: MKMapItem
    ) async -> (node: RouteNode, finishTime: Date)? {
        struct Candidate {
            let node: RouteNode
            let finish: Date
            let waiting: TimeInterval
            let returnEta: TimeInterval?
            let windowClose: Date
        }

        var candidates: [Candidate] = []

        for node in remaining {
            guard let window = node.schedule.window(for: currentTime) else { continue }
            guard let travelTo = await directionsClient.travelTime(
                from: current,
                to: node.mapItem,
                departure: currentTime
            ) else {
                continue
            }

            let arrival = currentTime.addingTimeInterval(travelTo)
            let startAt = max(arrival, window.open)
            let finish = startAt.addingTimeInterval(node.schedule.dwellSeconds)
            let waiting = max(0, startAt.timeIntervalSince(arrival))

            let returnEta = await directionsClient.travelTime(
                from: node.mapItem,
                to: origin,
                departure: finish
            )

            let candidate = Candidate(
                node: node,
                finish: finish,
                waiting: waiting,
                returnEta: returnEta,
                windowClose: window.close
            )
            candidates.append(candidate)
        }

        let feasible = candidates.filter { $0.finish <= $0.windowClose }
        if let best = feasible.min(by: { lhs, rhs in
            if lhs.finish != rhs.finish { return lhs.finish < rhs.finish }
            if lhs.windowClose != rhs.windowClose { return lhs.windowClose < rhs.windowClose }
            let lhsReturn = lhs.returnEta ?? .infinity
            let rhsReturn = rhs.returnEta ?? .infinity
            if lhsReturn != rhsReturn { return lhsReturn < rhsReturn }
            return lhs.waiting < rhs.waiting
        }) {
            return (best.node, best.finish)
        }

        if let fallback = candidates.min(by: { lhs, rhs in
            let lhsLateness = max(0, lhs.finish.timeIntervalSince(lhs.windowClose))
            let rhsLateness = max(0, rhs.finish.timeIntervalSince(rhs.windowClose))
            if lhsLateness != rhsLateness { return lhsLateness < rhsLateness }
            if lhs.finish != rhs.finish { return lhs.finish < rhs.finish }
            return (lhs.returnEta ?? .infinity) < (rhs.returnEta ?? .infinity)
        }) {
            return (fallback.node, fallback.finish)
        }

        return nil
    }

    private func buildRouteNodes() async -> ([RouteNode], [RunLocationSection], [RunLocationSection]) {
        let assigned = draftSections.filter { section in
            guard let locationId = section.location?.id else { return false }
            return !locationId.isEmpty
        }

        let unassigned = draftSections.filter { section in
            guard let locationId = section.location?.id else { return true }
            return locationId.isEmpty
        }

        var resolved: [RouteNode] = []
        var unresolved: [RunLocationSection] = []

        for section in assigned {
            guard let node = await routeNode(for: section) else {
                unresolved.append(section)
                continue
            }
            resolved.append(node)
        }

        return (resolved, unresolved, unassigned)
    }

    private func routeNode(for section: RunLocationSection) async -> RouteNode? {
        guard let location = section.location else {
            return nil
        }

        let schedule = viewModel.schedule(for: location.id)
        let resolvedAddress = schedule?.address ?? location.address ?? section.subtitle

        let address = (resolvedAddress ?? section.title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }

        guard let mapItem = await mapItem(for: address) else {
            return nil
        }

        return RouteNode(
            id: location.id,
            section: section,
            address: address,
            mapItem: mapItem,
            schedule: resolvedSchedule(for: location.id, fallback: location)
        )
    }

    private func resolvedSchedule(for locationId: String?, fallback location: RunDetail.Location?) -> ResolvedSchedule {
        let schedule = viewModel.schedule(for: locationId)
        return ResolvedSchedule(
            openingMinutes: schedule?.openingMinutes ?? location?.openingTimeMinutes,
            closingMinutes: schedule?.closingMinutes ?? location?.closingTimeMinutes,
            dwellMinutes: schedule?.dwellMinutes ?? location?.dwellTimeMinutes
        )
    }

    private func mapItem(for address: String) async -> MKMapItem? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = .address

        var attempt = 0
        let maxBackoff: UInt64 = 15_000_000_000

        while !Task.isCancelled {
            do {
                let response = try await MKLocalSearch(request: request).start()
                await MainActor.run {
                    didHitMapSearchThrottle = false
                }
                return response.mapItems.first
            } catch {
                if isMapsThrottleError(error) {
                    attempt += 1
                    let delay = min(UInt64(attempt) * 1_500_000_000, maxBackoff)
                    await MainActor.run {
                        didHitMapSearchThrottle = true
                    }
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                break
            }
        }

        return nil
    }

    private func isMapsThrottleError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if let mkError = error as? MKError, mkError.code == .loadingThrottled {
            return true
        }
        if nsError.domain == "GEOErrorDomain" {
            return true
        }
        if nsError.domain == MKError.errorDomain && nsError.code == MKError.Code.loadingThrottled.rawValue {
            return true
        }
        let description = nsError.localizedDescription.lowercased()
        return description.contains("throttl") || description.contains("limit")
    }

    private var companyStartAddress: String? {
        let trimmed = viewModel.companyLocation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func refreshTravelEstimates() async {
        guard let companyAddress = companyStartAddress else {
            await MainActor.run {
                inboundLegs = [:]
                totalTravelSeconds = nil
                isCalculatingTravel = false
                didHitMapSearchThrottle = false
                routePreviewAnnotations = []
                routePolyline = []
                mapCameraPosition = .automatic
            }
            return
        }

        guard let companyItem = await mapItem(for: companyAddress) else {
            await MainActor.run {
                if didHitMapSearchThrottle {
                    pushErrorBanner("Maps lookups are temporarily rate limited. Travel times will refresh soon.")
                }
                isCalculatingTravel = false
                routePreviewAnnotations = []
                routePolyline = []
                mapCameraPosition = .automatic
            }
            return
        }

        await MainActor.run {
            isCalculatingTravel = true
        }

        let nodes = await sectionsToNodes()
        await updateRoutePreview(companyItem: companyItem, nodes: nodes)
        var legs: [String: RouteLeg] = [:]
        var total: TimeInterval = 0
        var previousItem = companyItem
        var previousLabel = "Shop"
        var accumulatedStart = startTime

        for node in nodes {
            guard let eta = await directionsClient.travelTime(
                from: previousItem,
                to: node.mapItem,
                departure: accumulatedStart
            ) else { continue }

            total += eta
            let arrival = accumulatedStart.addingTimeInterval(eta)
            let window = node.schedule.window(for: accumulatedStart) ?? (open: arrival, close: arrival)
            let startAt = max(arrival, window.open)
            let finish = startAt.addingTimeInterval(node.schedule.dwellSeconds)

            accumulatedStart = finish
            legs[node.section.id] = RouteLeg(
                id: UUID(),
                fromLabel: previousLabel,
                toLabel: node.section.title,
                etaSeconds: eta
            )
            previousItem = node.mapItem
            previousLabel = node.section.title
        }

        if let backEta = await directionsClient.travelTime(
            from: previousItem,
            to: companyItem,
            departure: accumulatedStart
        ) {
            total += backEta
        }

        await MainActor.run {
            inboundLegs = legs
            totalTravelSeconds = total > 0 ? total : nil
            isCalculatingTravel = false
        }
    }

    private func updateRoutePreview(companyItem: MKMapItem, nodes: [RouteNode]) async {
        let annotations = buildRouteAnnotations(companyItem: companyItem, nodes: nodes)
        let polyline = buildRoutePolyline(companyItem: companyItem, nodes: nodes)
        let region = routeRegion(for: polyline)

        await MainActor.run {
            routePreviewAnnotations = annotations
            routePolyline = polyline
            if let region {
                mapCameraPosition = .region(region)
            }
        }
    }

    private func buildRouteAnnotations(companyItem: MKMapItem, nodes: [RouteNode]) -> [RouteAnnotation] {
        var annotations: [RouteAnnotation] = []
        if let shopCoordinate = coordinate(for: companyItem), CLLocationCoordinate2DIsValid(shopCoordinate) {
            annotations.append(
                RouteAnnotation(
                    id: "shop",
                    title: "Shop",
                    subtitle: companyStartAddress,
                    coordinate: shopCoordinate,
                    kind: .shop
                )
            )
        }

        for (index, node) in nodes.enumerated() {
            guard let coordinate = coordinate(for: node.mapItem), CLLocationCoordinate2DIsValid(coordinate) else { continue }
            annotations.append(
                RouteAnnotation(
                    id: node.section.id,
                    title: node.section.title,
                    subtitle: node.address,
                    coordinate: coordinate,
                    kind: .stop(order: index + 1)
                )
            )
        }

        return annotations
    }

    private func buildRoutePolyline(companyItem: MKMapItem, nodes: [RouteNode]) -> [CLLocationCoordinate2D] {
        guard let shopCoordinate = coordinate(for: companyItem), CLLocationCoordinate2DIsValid(shopCoordinate) else {
            return []
        }

        var coordinates: [CLLocationCoordinate2D] = [shopCoordinate]

        for node in nodes {
            if let coord = coordinate(for: node.mapItem), CLLocationCoordinate2DIsValid(coord) {
                coordinates.append(coord)
            }
        }

        coordinates.append(shopCoordinate) // Return to shop
        return coordinates
    }

    private func routeRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        let valid = coordinates.filter(CLLocationCoordinate2DIsValid)
        guard let first = valid.first else { return nil }

        if valid.count == 1 {
            return MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }

        let latitudes = valid.map(\.latitude)
        let longitudes = valid.map(\.longitude)

        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max() else {
            return nil
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.02)
        )

        return MKCoordinateRegion(center: center, span: span)
    }

    private func coordinate(for mapItem: MKMapItem) -> CLLocationCoordinate2D? {
        let coordinate = mapItem.location.coordinate
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private func sectionsToNodes() async -> [RouteNode] {
        var nodes: [RouteNode] = []
        for section in draftSections {
            if let node = await routeNode(for: section) {
                nodes.append(node)
            }
        }
        return nodes
    }

    private func travelDisplay(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "N/A" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "\(Int(seconds/60)) min"
    }

    private func travelRow(for leg: RouteLeg, isFirst: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "car.fill")
                .foregroundColor(.blue)
            Text(travelDisplay(leg.etaSeconds))
                .font(.footnote.weight(.semibold))
            Spacer()
            Text("\(isFirst ? "Shop" : leg.fromLabel) → \(leg.toLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func isFirst(_ index: Int) -> Bool {
        index == 0
    }

    private struct RouteLeg: Identifiable {
        let id: UUID
        let fromLabel: String
        let toLabel: String
        let etaSeconds: TimeInterval?
    }

    private var optimiseLabel: String {
        if isSaving { return "Saving" }
        if isOptimizing { return "Optimising" }
        if isCalculatingTravel { return "Calculating" }
        return "Optimise"
    }

    // Fetches ETAs while respecting MapKit throttling by backing off without caching results.
    private actor RateLimitedDirections {
        private var etaTimestamps: [Date] = []
        private let window: TimeInterval = 60
        private let limit = 50

        func travelTime(from source: MKMapItem, to destination: MKMapItem, departure: Date) async -> TimeInterval? {
            var attempt = 0
            let maxBackoff: UInt64 = 15_000_000_000

            while !Task.isCancelled {
                if let delay = throttleDelay(since: Date()) {
                    try? await Task.sleep(nanoseconds: toNanoseconds(delay))
                    continue
                }

                record(now: Date())

                do {
                    let request = MKDirections.Request()
                    request.source = source
                    request.destination = destination
                    request.transportType = .automobile
                    request.departureDate = departure

                    let eta = try await MKDirections(request: request).calculateETA()
                    return eta.expectedTravelTime
                } catch {
                    if shouldRetry(after: error) {
                        attempt += 1
                        let throttleDelayNs = toNanoseconds(throttleDelay(since: Date()) ?? 0)
                        let backoff = min(UInt64(max(attempt, 1)) * 1_500_000_000, maxBackoff)
                        let wait = max(backoff, throttleDelayNs)
                        try? await Task.sleep(nanoseconds: wait)
                        continue
                    }
                    return nil
                }
            }

            return nil
        }

        private func throttleDelay(since now: Date) -> TimeInterval? {
            etaTimestamps = etaTimestamps.filter { now.timeIntervalSince($0) < window }
            guard etaTimestamps.count >= limit, let oldest = etaTimestamps.min() else { return nil }
            let elapsed = now.timeIntervalSince(oldest)
            return max(0, window - elapsed)
        }

        private func record(now: Date) {
            etaTimestamps.append(now)
        }

        private func toNanoseconds(_ seconds: TimeInterval) -> UInt64 {
            guard seconds > 0 else { return 0 }
            return UInt64(seconds * 1_000_000_000)
        }

        private func shouldRetry(after error: Error) -> Bool {
            let nsError = error as NSError
            if let mkError = error as? MKError, mkError.code == .loadingThrottled {
                return true
            }
            if nsError.domain == "GEOErrorDomain" {
                return true
            }
            if nsError.domain == MKError.errorDomain && nsError.code == MKError.Code.loadingThrottled.rawValue {
                return true
            }
            let description = nsError.localizedDescription.lowercased()
            return description.contains("throttl") || description.contains("limit")
        }
    }

    private struct RouteStartTimeStore {
        private let defaults = UserDefaults.standard

        func load(for runId: String) -> Date? {
            defaults.object(forKey: key(for: runId)) as? Date
        }

        func save(_ date: Date, for runId: String) {
            defaults.set(date, forKey: key(for: runId))
        }

        private func key(for runId: String) -> String {
            "route_start_time_\(runId)"
        }
    }
}

struct PendingPickEntriesView: View {
    @ObservedObject var viewModel: RunDetailViewModel
    let runId: String
    let session: AuthSession
    let service: RunsServicing

    @State private var selectedLocationFilter: String?
    @State private var selectedMachineFilter: String?
    @State private var updatingPickIds: Set<String> = []
    @State private var pickStatusToggleTrigger = false

    private var locations: [RunDetail.Location] {
        var lookup: [String: RunDetail.Location] = [:]
        for item in viewModel.pendingPickItems {
            if let location = item.location ?? item.machine?.location {
                lookup[location.id] = location
            }
        }
        return lookup.values.sorted { lhs, rhs in
            let lhsLabel = locationDisplayName(lhs)
            let rhsLabel = locationDisplayName(rhs)
            return lhsLabel.localizedCaseInsensitiveCompare(rhsLabel) == .orderedAscending
        }
    }

    private var allMachines: [RunDetail.Machine] {
        var lookup: [String: RunDetail.Machine] = [:]
        for item in viewModel.pendingPickItems {
            if let machine = item.machine {
                lookup[machine.id] = machine
            }
        }
        return lookup.values.sorted { lhs, rhs in
            lhs.code.localizedCaseInsensitiveCompare(rhs.code) == .orderedAscending
        }
    }

    private var visibleMachines: [RunDetail.Machine] {
        guard let locationId = selectedLocationFilter else {
            return allMachines
        }
        return allMachines.filter { machine in
            machine.location?.id == locationId
        }
    }

    private var filteredPickItems: [RunDetail.PickItem] {
        let baseItems = viewModel.pendingPickItems
        let filteredByLocation: [RunDetail.PickItem]
        if let locationId = selectedLocationFilter {
            filteredByLocation = baseItems.filter { item in
                let resolvedId = item.location?.id ?? item.machine?.location?.id
                return resolvedId == locationId
            }
        } else {
            filteredByLocation = baseItems
        }

        let filteredByMachine: [RunDetail.PickItem]
        if let machineId = selectedMachineFilter {
            filteredByMachine = filteredByLocation.filter { $0.machine?.id == machineId }
        } else {
            filteredByMachine = filteredByLocation
        }

        let grouped = Dictionary(grouping: filteredByMachine) { item in
            item.machine?.id ?? "unknown"
        }

        let machineLookup = Dictionary(uniqueKeysWithValues: allMachines.map { ($0.id, $0) })

        let sortedMachineIds = grouped.keys.sorted { lhs, rhs in
            let lhsLabel = machineLookup[lhs]?.code ?? lhs
            let rhsLabel = machineLookup[rhs]?.code ?? rhs
            return lhsLabel.localizedCaseInsensitiveCompare(rhsLabel) == .orderedAscending
        }

        return sortedMachineIds.flatMap { machineId in
            let entries = grouped[machineId] ?? []
            return entries.sorted { first, second in
                first.coilItem.coil.code.localizedCaseInsensitiveCompare(second.coilItem.coil.code) == .orderedDescending
            }
        }
    }

    private var machineFilterLabel: String {
        guard let filter = selectedMachineFilter,
              let machine = allMachines.first(where: { $0.id == filter }) else {
            return "All Machines"
        }
        return machine.description ?? machine.code
    }

    private var locationFilterLabel: String {
        guard let filter = selectedLocationFilter,
              let location = locations.first(where: { $0.id == filter }) else {
            return "All Locations"
        }
        return locationDisplayName(location)
    }

    var body: some View {
        List {
            Section {
                filterControls

                if viewModel.isLoading && viewModel.pendingPickItems.isEmpty {
                    LoadingRow()
                } else if filteredPickItems.isEmpty {
                    Text("No pick entries are waiting to be packed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(filteredPickItems, id: \.id) { pickItem in
                        PickEntryRow(
                            pickItem: pickItem,
                            onToggle: {
                                HapticsService.shared.actionCompleted()
                                Task {
                                    await togglePickStatus(pickItem)
                                }
                            },
                            showsLocation: true
                        )
                        .sensoryFeedback(.selection, trigger: updatingPickIds.contains(pickItem.id) ? false : true)
                        .disabled(updatingPickIds.contains(pickItem.id))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Waiting to Pack")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.load(force: true)
        }
        .onChange(of: visibleMachines) { _, _ in
            guard let selection = selectedMachineFilter else { return }
            if visibleMachines.first(where: { $0.id == selection }) == nil {
                selectedMachineFilter = nil
            }
        }
        .onChange(of: locations) { _, _ in
            guard let selection = selectedLocationFilter else { return }
            if locations.first(where: { $0.id == selection }) == nil {
                selectedLocationFilter = nil
            }
        }
    }

    @ViewBuilder
    private var filterControls: some View {
        HStack {
            Menu {
                Button("All Locations") {
                    selectedLocationFilter = nil
                }
                if !locations.isEmpty {
                    Divider()
                    ForEach(locations, id: \.id) { location in
                        Button(locationDisplayName(location)) {
                            selectedLocationFilter = location.id
                        }
                    }
                }
            } label: {
                filterChip(label: locationFilterLabel)
            }
            .foregroundStyle(.secondary)

            Menu {
                Button("All Machines") {
                    selectedMachineFilter = nil
                }
                let machines = visibleMachines
                if !machines.isEmpty {
                    Divider()
                    ForEach(machines, id: \.id) { machine in
                        Button(machine.description ?? machine.code) {
                            selectedMachineFilter = machine.id
                        }
                    }
                }
            } label: {
                filterChip(label: machineFilterLabel)
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func locationDisplayName(_ location: RunDetail.Location) -> String {
        let trimmedName = location.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = trimmedName, !name.isEmpty {
            return name
        }
        let trimmedAddress = location.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let address = trimmedAddress, !address.isEmpty {
            return address
        }
        return "Location"
    }

    private func togglePickStatus(_ pickItem: RunDetail.PickItem) async {
        updatingPickIds.insert(pickItem.id)
        let newIsPicked = !pickItem.isPicked

        do {
            try await service.updatePickItemStatuses(
                runId: runId,
                pickIds: [pickItem.id],
                isPicked: newIsPicked,
                credentials: session.credentials
            )
            await viewModel.load(force: true)
            // Trigger haptic feedback for successful pick status change
            pickStatusToggleTrigger.toggle()
        } catch {
            print("Failed to update pick status: \(error)")
        }

        _ = await MainActor.run {
            updatingPickIds.remove(pickItem.id)
        }
    }
}

#Preview {
    

    let credentials = AuthCredentials(
        accessToken: "preview-token",
        refreshToken: "preview-refresh",
        userID: "user-1",
        expiresAt: Date().addingTimeInterval(3600)
    )
    let profile = UserProfile(
        id: "user-1",
        email: "jordan@example.com",
        firstName: "Jordan",
        lastName: "Smith",
        phone: nil,
        role: "PICKER"
    )
    let session = AuthSession(credentials: credentials, profile: profile)

    return NavigationStack {
        RunDetailView(runId: "run-12345", session: session, service: PreviewRunsService())
            .environment(\.colorScheme, .light)
    }
}
