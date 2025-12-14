//
//  RunLocationDetailView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/26/2025.
//

import SwiftUI

enum CoilSortOrder: CaseIterable {
    case ascending
    case descending
    
    var displayName: String {
        switch self {
        case .ascending:
            return "Ascending"
        case .descending:
            return "Descending"
        }
    }

    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}

struct RunLocationDetailView: View {
    let detail: RunLocationDetail
    let runId: String
    let session: AuthSession
    let service: RunsServicing
    let viewModel: RunDetailViewModel
    let onPickStatusChanged: () async -> Void
    
    @State private var selectedMachineFilter: String?
    @State private var selectedCategoryFilter: String?
    @State private var coilSortOrder: CoilSortOrder = .descending
    @State private var updatingPickIds: Set<String> = []
    @State private var updatingSkuIds: Set<String> = []
    @State private var activeSheet: RunLocationDetailSheet?
    @State private var isResettingLocationPickStatuses = false
    @State private var confirmingLocationReset = false
    @Environment(\.openURL) private var openURL
    @AppStorage(DirectionsApp.storageKey) private var preferredDirectionsAppRawValue = DirectionsApp.appleMaps.rawValue
    
    @State private var selectedPickItemForCountPointer: RunDetail.PickItem?
    @State private var pickItemPendingDeletion: RunDetail.PickItem?
    @State private var pickItemPendingSubstitution: RunDetail.PickItem?
    @State private var locationNavigationTarget: RunLocationDetailSearchNavigation?
    @State private var machineNavigationTarget: RunLocationDetailMachineNavigation?

    private var overviewSummary: RunLocationOverviewSummary {
        RunLocationOverviewSummary(
            title: detail.section.title,
            address: detail.section.subtitle,
            machineCount: detail.section.machineCount,
            totalCoils: detail.section.totalCoils,
            packedCoils: detail.section.packedCoils,
            totalItems: detail.section.totalItems
        )
    }
    
    private var coldChestItems: [RunDetail.PickItem] {
        detail.pickItems.filter { pickItem in
            pickItem.sku?.isFreshOrFrozen == true
        }
    }

    private var machines: [RunDetail.Machine] {
        detail.machines
    }

    private var availableSkuCategories: [String] {
        var seen = Set<String>()
        var categories: [String] = []

        for category in detail.pickItems.compactMap({ $0.sku?.category?.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            guard !category.isEmpty, !seen.contains(category.lowercased()) else { continue }
            seen.insert(category.lowercased())
            categories.append(category)
        }

        return categories.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filteredPickItems: [RunDetail.PickItem] {
        let allPickItems = detail.pickItems
        let filteredItems = if let machineId = selectedMachineFilter {
            allPickItems.filter { $0.machine?.id == machineId }
        } else {
            allPickItems
        }

        let categoryFilteredItems = if let category = selectedCategoryFilter {
            filteredItems.filter { pickItem in
                guard let itemCategory = pickItem.sku?.category?.trimmingCharacters(in: .whitespacesAndNewlines), !itemCategory.isEmpty else {
                    return false
                }
                return itemCategory.caseInsensitiveCompare(category) == .orderedSame
            }
        } else {
            filteredItems
        }
        
        return categoryFilteredItems.sorted { item1, item2 in
            let coil1 = item1.coilItem.coil.code
            let coil2 = item2.coilItem.coil.code

            let comparison = coil1.compare(coil2, options: [.numeric, .caseInsensitive])

            switch (coilSortOrder, comparison) {
            case (.ascending, .orderedAscending), (.descending, .orderedDescending):
                return true
            case (.ascending, .orderedDescending), (.descending, .orderedAscending):
                return false
            case (_, .orderedSame):
                // Stable fallback so equal coils stay predictable
                return item1.id < item2.id
            default:
                return false
            }
        }
    }

    var body: some View {
        List {
            Section {
                RunLocationOverviewBento(
                    summary: overviewSummary,
                    machines: machines,
                    viewModel: viewModel,
                    onChocolateBoxesTap: {
                        activeSheet = .chocolateBoxes
                    },
                    onAddChocolateBoxTap: {
                        activeSheet = .addChocolateBox
                    },
                    coldChestItems: coldChestItems,
                    onLocationTap: {
                        navigateToSearchLocation()
                    },
                    onMachineTap: { machine in
                        navigateToMachineDetail(machine)
                    }
                )
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                Text("Location Overview")
            }

            Section {
                HStack {
                    Menu {
                        Button("All Machines") {
                            selectedMachineFilter = nil
                        }
                        Divider()
                        ForEach(machines, id: \.id) { machine in
                    Button(machine.description ?? machine.code) {
                        selectedMachineFilter = machine.id
                    }
                }
            } label: {
                filterChip(label: selectedMachineFilter == nil ? "All Machines" : (machines.first { $0.id == selectedMachineFilter }?.description ?? machines.first { $0.id == selectedMachineFilter }?.code ?? "Unknown"))
            }
            .foregroundStyle(.secondary)
            
            Menu {
                Button("All Categories") {
                    selectedCategoryFilter = nil
                }

                if !availableSkuCategories.isEmpty {
                    Divider()
                }

                ForEach(availableSkuCategories, id: \.self) { category in
                    Button(category) {
                        selectedCategoryFilter = category
                    }
                }
            } label: {
                filterChip(label: selectedCategoryFilter ?? "All Categories")
            }
            .foregroundStyle(.secondary)
            .disabled(availableSkuCategories.isEmpty)
            
            Spacer()

            Button {
                coilSortOrder.toggle()
            } label: {
                Image(systemName: coilSortOrder.displayName.contains("Ascending") ? "arrow.up" : "arrow.down")
                    .font(.footnote.weight(.semibold))
                    .padding(6)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
        }
                
                if filteredPickItems.isEmpty {
                    Text("No picks found.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(filteredPickItems, id: \.id) { pickItem in
                        let isUpdatingPick = updatingPickIds.contains(pickItem.id) || updatingSkuIds.contains(pickItem.sku?.id ?? "")
                        PickEntryRow(
                            pickItem: pickItem,
                            onToggle: {
                                Task {
                                    await togglePickStatus(pickItem)
                                }
                            }
                        )
                        .disabled(isUpdatingPick)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                pickItemPendingSubstitution = pickItem
                            } label: {
                                Label("Substitute", systemImage: "rectangle.2.swap")
                            }
                            .tint(.indigo)
                            
                            Button {
                                Task {
                                    await toggleColdChestStatus(pickItem)
                                }
                            } label: {
                                Label(
                                    pickItem.sku?.isFreshOrFrozen == true ? "Remove" : "Cold Chest",
                                    systemImage: "snowflake"
                                )
                            }
                            .tint(Theme.coldChestTint.opacity(pickItem.sku?.isFreshOrFrozen == true ? 1 : 0.9))
                            
                            Button {
                                selectedPickItemForCountPointer = pickItem
                            } label: {
                                Label("Edit Count", systemImage: "square.and.pencil")
                            }
                            .tint(.blue)
                            
                            Button {
                                pickItemPendingDeletion = pickItem
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
            } header: {
                Text("Picks")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(detail.section.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .chocolateBoxes:
                ChocolateBoxesSheet(viewModel: viewModel, locationMachines: machines)
                    .presentationDetents([.fraction(0.5), .large])
                    .presentationDragIndicator(.visible)
            case .addChocolateBox:
                AddChocolateBoxSheet(viewModel: viewModel, locationMachines: machines)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $selectedPickItemForCountPointer) { pickItem in
            CountPointerSelectionSheet(
                pickItem: pickItem,
                onDismiss: {
                    selectedPickItemForCountPointer = nil
                },
                onPointerSelected: { newPointer in
                    Task {
                        await updateCountPointer(pickItem, newPointer: newPointer)
                    }
                },
                onOverrideSaved: { overrideValue in
                    await updateOverrideCount(pickItem, newOverride: overrideValue)
                },
                viewModel: viewModel
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $pickItemPendingSubstitution) { pickItem in
            SubstituteSkuSearchView(
                pickItem: pickItem,
                runId: runId,
                session: session,
                runsService: service,
                onPickStatusChanged: onPickStatusChanged
            )
        }

        .alert(item: $pickItemPendingDeletion) { pickItem in
            Alert(
                title: Text("Are you sure?"),
                message: Text("This will permanently delete \(pickItem.sku?.name ?? "this pick entry")."),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        await deletePickItem(pickItem)
                    }
                },
                secondaryButton: .cancel {
                    pickItemPendingDeletion = nil
                }
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isResettingLocationPickStatuses {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Button {
                        confirmingLocationReset = true
                    } label: {
                        Label("Reset Packed Status", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!canResetLocationPickStatuses)
                    .accessibilityLabel("Reset packed status for this location")
                }

                Button {
                    openDirections()
                } label: {
                    Image(systemName: "map")
                }
                .disabled(locationDirectionsQuery == nil)
                .accessibilityLabel("Get directions")
            }
        }
        .alert("Reset Packed Status?", isPresented: $confirmingLocationReset) {
            Button("Reset", role: .destructive) {
                Task {
                    await resetLocationPickStatuses()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This resets only the packed picks for \(detail.section.title).")
        }
        .navigationDestination(item: $locationNavigationTarget) { target in
            SearchLocationDetailView(locationId: target.id, session: session)
        }
        .navigationDestination(item: $machineNavigationTarget) { target in
            MachineDetailView(machineId: target.id, session: session)
        }
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
            await onPickStatusChanged()
        } catch {
            // Handle error - could show an alert
            print("Failed to update pick status: \(error)")
        }
        
        _ = await MainActor.run {
            updatingPickIds.remove(pickItem.id)
        }
    }
    
    private func toggleColdChestStatus(_ pickItem: RunDetail.PickItem) async {
        guard let skuId = pickItem.sku?.id else { return }
        
        updatingSkuIds.insert(skuId)
        
        let newFreshStatus = !(pickItem.sku?.isFreshOrFrozen ?? false)
        
        do {
            try await service.updateSkuColdChestStatus(
                skuId: skuId,
                isFreshOrFrozen: newFreshStatus,
                credentials: session.credentials
            )
            await onPickStatusChanged()
        } catch {
            // Handle error - could show an alert
            print("Failed to update SKU cold chest status: \(error)")
        }
        
        _ = await MainActor.run {
            updatingSkuIds.remove(skuId)
        }
    }
    
    private func deletePickItem(_ pickItem: RunDetail.PickItem) async {
        updatingPickIds.insert(pickItem.id)
        
        do {
            try await service.deletePickItem(
                runId: runId,
                pickId: pickItem.id,
                credentials: session.credentials
            )
            await onPickStatusChanged()
        } catch {
            print("Failed to delete pick entry: \(error)")
        }
        
        _ = await MainActor.run {
            updatingPickIds.remove(pickItem.id)
            if pickItemPendingDeletion?.id == pickItem.id {
                pickItemPendingDeletion = nil
            }
        }
    }
    
    private func updateCountPointer(_ pickItem: RunDetail.PickItem, newPointer: String) async {
        guard let skuId = pickItem.sku?.id else { return }
        
        updatingSkuIds.insert(skuId)
        
        do {
            try await service.updateSkuCountPointer(
                skuId: skuId,
                countNeededPointer: newPointer,
                credentials: session.credentials
            )
            // Wait for the data to refresh before closing the sheet
            await onPickStatusChanged()
            await MainActor.run {
                selectedPickItemForCountPointer = nil
            }
        } catch {
            // Handle error - could show an alert
            print("Failed to update SKU count pointer: \(error)")
        }
        
        _ = await MainActor.run {
            updatingSkuIds.remove(skuId)
        }
    }
    
    private func updateOverrideCount(_ pickItem: RunDetail.PickItem, newOverride: Int?) async {
        updatingPickIds.insert(pickItem.id)
        
        do {
            try await service.updatePickEntryOverride(
                runId: runId,
                pickId: pickItem.id,
                overrideCount: newOverride,
                credentials: session.credentials
            )
            await onPickStatusChanged()
            await MainActor.run {
                selectedPickItemForCountPointer = nil
            }
        } catch {
            print("Failed to update pick override: \(error)")
        }
        
        _ = await MainActor.run {
            updatingPickIds.remove(pickItem.id)
        }
    }
    
    private var preferredDirectionsApp: DirectionsApp {
        DirectionsApp(rawValue: preferredDirectionsAppRawValue) ?? .appleMaps
    }
    
    private var locationDirectionsQuery: String? {
        let trimmedAddress = detail.section.location?.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedAddress.isEmpty {
            return trimmedAddress
        }
        
        let trimmedTitle = detail.section.location?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? detail.section.title
        let title = trimmedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty || detail.section.location == nil ? nil : title
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

    private func navigateToSearchLocation() {
        guard let locationId = detail.section.location?.id, !locationId.isEmpty else {
            return
        }
        locationNavigationTarget = RunLocationDetailSearchNavigation(id: locationId)
    }

    private func navigateToMachineDetail(_ machine: RunDetail.Machine) {
        guard !machine.id.isEmpty else {
            return
        }
        machineNavigationTarget = RunLocationDetailMachineNavigation(id: machine.id)
    }
    
    private var locationPickItemsSnapshot: [RunDetail.PickItem] {
        if let latestDetail = viewModel.locationDetail(for: detail.section.id) {
            return latestDetail.pickItems
        }
        return detail.pickItems
    }
    
    private var canResetLocationPickStatuses: Bool {
        locationPickItemsSnapshot.contains { $0.isPicked }
    }
    
    @MainActor
    private func resetLocationPickStatuses() async {
        guard !isResettingLocationPickStatuses else { return }
        isResettingLocationPickStatuses = true
        defer { isResettingLocationPickStatuses = false }
        
        _ = await viewModel.resetPickStatuses(for: locationPickItemsSnapshot)
    }
}

private struct RunLocationDetailSearchNavigation: Identifiable, Hashable {
    let id: String
}

private struct RunLocationDetailMachineNavigation: Identifiable, Hashable {
    let id: String
}

private enum RunLocationDetailSheet: Identifiable {
    case chocolateBoxes
    case addChocolateBox
    
    var id: String {
        switch self {
        case .chocolateBoxes:
            return "chocolateBoxes"
        case .addChocolateBox:
            return "addChocolateBox"
        }
    }
}

struct CountPointerSelectionSheet: View {
    let pickItem: RunDetail.PickItem
    let onDismiss: () -> Void
    let onPointerSelected: (String) -> Void
    let onOverrideSaved: (Int?) async -> Void
    @ObservedObject var viewModel: RunDetailViewModel
    
    @State private var overrideInput: String = ""
    @State private var isSavingOverride = false
    @State private var overrideError: String?
    
    private let countPointers = [
        ("current", "Current", "Current inventory count"),
        ("par", "PAR", "Par level count"),
        ("need", "Need", "Needed count"),
        ("forecast", "Forecast", "Forecast count"),
        ("total", "Total", "Total count")
    ]
    
    private var latestPickItem: RunDetail.PickItem {
        viewModel.detail?.pickItems.first { $0.id == pickItem.id } ?? pickItem
    }
    
    private var currentSelection: String {
        latestPickItem.sku?.countNeededPointer ?? "total"
    }
    
    private var currentOverride: Int? {
        latestPickItem.overrideCount
    }
    
    private var defaultPointerCount: Int? {
        let pointerKey = latestPickItem.sku?.countNeededPointer ?? "total"
        return latestPickItem.countForPointer(pointerKey) ?? latestPickItem.count
    }
    
    private var parsedOverride: Int? {
        let trimmed = overrideInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(countPointers, id: \.0) { pointer in
                        CountPointerRow(
                            pointer: pointer,
                            currentCount: latestPickItem.countForPointer(pointer.0),
                            isSelected: pointer.0 == currentSelection
                        ) {
                            if !isSavingOverride {
                                onPointerSelected(pointer.0)
                            }
                        }
                    }
                } header: {
                    Text("Select Count Source")
                } footer: {
                    Text("Choose which field determines the needed count for this SKU.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Override count", text: $overrideInput)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        
                        if let defaultPointerCount {
                            Text("Default from \(currentSelection.uppercased()): \(defaultPointerCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let overrideError {
                            Text(overrideError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Manual Override")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(pickItem.sku?.name ?? "Unknown SKU")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if currentOverride != nil {
                        Button("Clear Override") {
                            clearOverride()
                        }
                        .disabled(isSavingOverride)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    let hasTypedOverride = parsedOverride != nil
                    Button(hasTypedOverride ? "Save" : "Done") {
                        if hasTypedOverride {
                            saveOverride()
                        } else {
                            onDismiss()
                        }
                    }
                    .disabled(isSavingOverride)
                }
            }
        }
        .onAppear {
            overrideInput = currentOverride.map(String.init) ?? ""
        }
        .onChange(of: currentOverride) { _, newValue in
            overrideInput = newValue.map(String.init) ?? ""
        }
    }
    
    private func saveOverride() {
        overrideError = nil
        
        guard let resolved = parsedOverride, resolved >= 0 else {
            overrideError = "Enter a whole number 0 or greater."
            return
        }
        
        Task {
            isSavingOverride = true
            defer { isSavingOverride = false }
            await onOverrideSaved(resolved)
        }
    }
    
    private func clearOverride() {
        Task {
            isSavingOverride = true
            defer { isSavingOverride = false }
            await onOverrideSaved(nil)
            overrideInput = ""
        }
    }
}

private struct CountPointerRow: View {
    let pointer: (String, String, String)
    let currentCount: Int?
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pointer.1)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(pointer.2)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let count = currentCount {
                    Text("\(count)")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                } else {
                    Text("N/A")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(PlainButtonStyle())
    }
}

struct PickEntryRow: View {
    let pickItem: RunDetail.PickItem
    let onToggle: () -> Void
    var showsLocation: Bool = false

    init(
        pickItem: RunDetail.PickItem,
        onToggle: @escaping () -> Void,
        showsLocation: Bool = false
    ) {
        self.pickItem = pickItem
        self.onToggle = onToggle
        self.showsLocation = showsLocation
    }

    private var locationLabel: String? {
        if let explicitName = pickItem.location?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !explicitName.isEmpty {
            return explicitName
        }

        if let machineLocationName = pickItem.machine?.location?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !machineLocationName.isEmpty {
            return machineLocationName
        }

        if let address = pickItem.location?.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
            return address
        }

        return nil
    }
    
    var body: some View {
        HStack {
            Button {
                onToggle()
            } label: {
                ZStack {
                    Circle()
                        .stroke(pickItem.isPicked ? Color.green : Color.gray, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    
                    if pickItem.isPicked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if let sku = pickItem.sku {
                        Text("\(sku.name)\(sku.type != "General" ? ", \(sku.type)" : " ")")
                            .font(.headline)
                            .fontWeight(.semibold)
                        if sku.type == "General" {
                            Text(sku.code)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .fontWeight(.regular)
                        }
                    } else {
                        Text("Unknown")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .fontWeight(.regular)
                    }
                }
                
                FlowLayout(spacing: 6) {
                    if showsLocation, let locationLabel {
                        InfoChip(text: locationLabel)
                    }
                    
                    if let machineCode = pickItem.machine?.description {
                        InfoChip(text: machineCode)
                    }
                    
                    InfoChip(title: "Coil", text: pickItem.coilItem.coil.code)
                    
                    if let category = pickItem.sku?.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
                        let chipColour = colorForCategoryChip(category)
                        InfoChip(
                            text: category,
                            colour: chipColour.opacity(0.2),
                            foregroundColour: chipColour,
                            icon: "tray.fill"
                        )
                    }

                    if pickItem.sku?.isFreshOrFrozen == true {
                        InfoChip(
                            text: "Cold Chest",
                            colour: Theme.coldChestTint.opacity(0.2),
                            foregroundColour: Theme.coldChestTint,
                            icon: "snowflake"
                        )
                    }
                }
            }
            .padding(.vertical, 6)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(pickItem.count)")
                    .font(.title)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                if pickItem.hasOverride {
                    Text("Override")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

private extension PickEntryRow {
    @ViewBuilder
    func detailChip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.secondary)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
    }
}


private func colorForCategoryChip(_ category: String) -> Color {
    let palette: [Color] = [
        Color(red: 0.05, green: 0.30, blue: 0.59), // deep indigo
        Color(red: 0.12, green: 0.45, blue: 0.25), // forest green
        Color(red: 0.70, green: 0.15, blue: 0.35), // rich berry
        Color(red: 0.40, green: 0.14, blue: 0.54), // plum
        Color(red: 0.85, green: 0.40, blue: 0.12), // burnt orange
        Color(red: 0.60, green: 0.21, blue: 0.16), // brick red
        Color(red: 0.16, green: 0.45, blue: 0.56), // slate teal
        Color(red: 0.38, green: 0.52, blue: 0.73), // storm blue
    ]

    let stableHash = category.unicodeScalars.reduce(0) { result, scalar in
        (result &* 31) &+ Int(scalar.value)
    }
    let paletteIndex = abs(stableHash) % palette.count
    return palette[paletteIndex]
}



#Preview {
    let location = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
    let machineType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
    let machineA = RunDetail.Machine(id: "machine-1", code: "A-01", description: "Lobby", machineType: machineType, location: location)
    let machineB = RunDetail.Machine(id: "machine-2", code: "B-12", description: "Breakroom", machineType: machineType, location: location)

    let coilA = RunDetail.Coil(id: "coil-1", code: "C1", machineId: machineA.id)
    let coilB = RunDetail.Coil(id: "coil-2", code: "C2", machineId: machineB.id)

    let coilItemA = RunDetail.CoilItem(id: "coil-item-1", par: 12, coil: coilA)
    let coilItemB = RunDetail.CoilItem(id: "coil-item-2", par: 8, coil: coilB)

    let sku = RunDetail.Sku(
        id: "sku-1",
        code: "SKU-001",
        name: "Trail Mix",
        type: "Snack",
        category: "Snacks",
        weight: nil,
        labelColour: nil,
        isFreshOrFrozen: false,
        countNeededPointer: "total"
    )

    let pickA = RunDetail.PickItem(id: "pick-1", count: 6, overrideCount: nil, current: 8, par: 10, need: 6, forecast: 7, total: 12, isPicked: true, pickedAt: Date(), coilItem: coilItemA, sku: sku, machine: machineA, location: location, packingSessionId: nil)
    let pickB = RunDetail.PickItem(id: "pick-2", count: 4, overrideCount: 5, current: 3, par: 8, need: 4, forecast: 5, total: 9, isPicked: false, pickedAt: nil, coilItem: coilItemB, sku: sku, machine: machineB, location: location, packingSessionId: nil)

    let section = RunLocationSection(
        id: location.id,
        location: location,
        machineCount: 2,
        totalCoils: 2,
        packedCoils: 1,
        totalItems: 10
    )

    let detail = RunLocationDetail(
        section: section,
        machines: [machineA, machineB],
        pickItemsByMachine: [
            machineA.id: [pickA],
            machineB.id: [pickB],
        ]
    )

    NavigationStack {
        RunLocationDetailView(
            detail: detail,
            runId: "preview-run",
            session: AuthSession(
                credentials: AuthCredentials(
                    accessToken: "preview-token",
                    refreshToken: "preview-refresh",
                    userID: "user-1",
                    expiresAt: Date().addingTimeInterval(3600)
                ),
                profile: UserProfile(
                    id: "user-1",
                    email: "preview@example.com",
                    firstName: "Preview",
                    lastName: "User",
                    phone: nil,
                    role: "PICKER"
                )
            ),
            service: PreviewRunsService(),
            viewModel: RunDetailViewModel(runId: "preview-run", session: AuthSession(
                credentials: AuthCredentials(
                    accessToken: "preview-token",
                    refreshToken: "preview-refresh",
                    userID: "user-1",
                    expiresAt: Date().addingTimeInterval(3600)
                ),
                profile: UserProfile(
                    id: "user-1",
                    email: "preview@example.com",
                    firstName: "Preview",
                    lastName: "User",
                    phone: nil,
                    role: "PICKER"
                )
            ), service: PreviewRunsService()),
            onPickStatusChanged: {}
        )
    }
}
