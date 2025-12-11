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
        let cheeseSkuChips = viewModel.cheeseSkuChips(for: section.id)
        let chocolateBoxesLabel = chocolateBoxDisplay(for: section)
        let locationDetail = viewModel.locationDetail(for: section.id)
        let machines = locationDetail?.machines ?? []

        Group {
            if let locationDetail {
                NavigationLink {
                    RunLocationDetailView(
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
                        cheeseSkuChips: cheeseSkuChips,
                        chocolateBoxLabel: chocolateBoxesLabel,
                        isProcessing: isDeleting
                    )
                }
                .disabled(isDeleting)
            } else {
                LocationSummaryRow(
                    section: section,
                    machines: machines,
                    cheeseSkuChips: cheeseSkuChips,
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
    var cheeseSkuChips: [CheeseSkuChip] = []
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
                
                if section.remainingCoils > 0 {
                    InfoChip(text: "\(section.remainingCoils) remaining")
                } else {
                    InfoChip(text: "All Packed", colour: .green.opacity(0.15), foregroundColour: .green)
                }

                ForEach(machineTypeChips) { chip in
                    InfoChip(
                        text: chip.label,
                        colour: Color.indigo.opacity(0.15),
                        foregroundColour: Color.indigo,
                        icon: "building"
                    )
                }

                ForEach(cheeseSkuChips) { chip in
                    InfoChip(
                        title: chip.label,
                        text: "\(chip.count)",
                        colour: Color(.systemGray5),
                        foregroundColour: Color.secondary,
                        icon: "rectangle.fill",
                        iconColour: chip.colour
                    )
                }

                if let chocolateBoxLabel {
                    InfoChip(
                        text: chocolateBoxLabel,
                        colour: Color.brown.opacity(0.15),
                        foregroundColour: Color.brown,
                        icon: "shippingbox.fill"
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
