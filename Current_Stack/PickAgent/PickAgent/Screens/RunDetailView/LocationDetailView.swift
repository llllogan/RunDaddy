//
//  LocationDetailView.swift
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
            return "Coil: Decending"
        case .descending:
            return "Coil: Ascending"
        }
    }
}

struct LocationDetailView: View {
    let detail: RunLocationDetail
    let runId: String
    let session: AuthSession
    let service: RunsServicing
    let viewModel: RunDetailViewModel
    let onPickStatusChanged: () async -> Void
    
    @State private var selectedMachineFilter: String?
    @State private var coilSortOrder: CoilSortOrder = .descending
    @State private var updatingPickIds: Set<String> = []
    @State private var updatingSkuIds: Set<String> = []
    @State private var showingChocolateBoxesSheet = false
    @State private var isResettingLocationPickStatuses = false
    @Environment(\.openURL) private var openURL
    @AppStorage(DirectionsApp.storageKey) private var preferredDirectionsAppRawValue = DirectionsApp.appleMaps.rawValue
    
    @State private var selectedPickItemForCountPointer: RunDetail.PickItem?
    @State private var pickItemPendingDeletion: RunDetail.PickItem?

    private var overviewSummary: LocationOverviewSummary {
        LocationOverviewSummary(
            title: detail.section.title,
            address: detail.section.subtitle,
            machineCount: detail.section.machineCount,
            totalCoils: detail.section.totalCoils,
            packedCoils: detail.section.packedCoils,
            totalItems: detail.section.totalItems
        )
    }
    
    private var cheeseItems: [RunDetail.PickItem] {
        detail.pickItems.filter { pickItem in
            pickItem.sku?.isCheeseAndCrackers == true
        }
    }

    private var machines: [RunDetail.Machine] {
        detail.machines
    }

    private var filteredPickItems: [RunDetail.PickItem] {
        let allPickItems = detail.pickItems
        let filteredItems = if let machineId = selectedMachineFilter {
            allPickItems.filter { $0.machine?.id == machineId }
        } else {
            allPickItems
        }
        
        // Group by machine first, then sort within each machine group
        let groupedByMachine = Dictionary(grouping: filteredItems) { item in
            item.machine?.id ?? "unknown"
        }
        
        // Sort machines by their code/description for consistent ordering
        let sortedMachineIds = groupedByMachine.keys.sorted { machineId1, machineId2 in
            let machine1 = machines.first { $0.id == machineId1 }
            let machine2 = machines.first { $0.id == machineId2 }
            
            let code1 = machine1?.code ?? machineId1
            let code2 = machine2?.code ?? machineId2
            
            return code1.localizedCaseInsensitiveCompare(code2) == .orderedAscending
        }
        
        // Flatten the groups while maintaining coil sort order within each machine
        var result: [RunDetail.PickItem] = []
        for machineId in sortedMachineIds {
            let machineItems = groupedByMachine[machineId] ?? []
            let sortedItems = machineItems.sorted { item1, item2 in
                let coil1 = item1.coilItem.coil.code
                let coil2 = item2.coilItem.coil.code
                
                switch coilSortOrder {
                case .ascending:
                    return coil1.localizedCaseInsensitiveCompare(coil2) == .orderedAscending
                case .descending:
                    return coil1.localizedCaseInsensitiveCompare(coil2) == .orderedDescending
                }
            }
            result.append(contentsOf: sortedItems)
        }
        
        return result
    }

    var body: some View {
        List {
            Section {
                LocationOverviewBento(
                    summary: overviewSummary, 
                    machines: machines, 
                    viewModel: viewModel, 
                    onChocolateBoxesTap: {
                        showingChocolateBoxesSheet = true
                    },
                    cheeseItems: cheeseItems
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
                        HStack {
                            Text(selectedMachineFilter == nil ? "All Machines" : (machines.first { $0.id == selectedMachineFilter }?.description ?? machines.first { $0.id == selectedMachineFilter }?.code ?? "Unknown"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                    }
                    
                    Menu {
                        ForEach(CoilSortOrder.allCases, id: \.self) { order in
                            Button(order.displayName) {
                                coilSortOrder = order
                            }
                        }
                    } label: {
                        HStack {
                            Text(coilSortOrder.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                }
                
                if filteredPickItems.isEmpty {
                    Text("No picks found.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(filteredPickItems, id: \.id) { pickItem in
                        PickEntryRow(
                            pickItem: pickItem,
                            onToggle: {
                                Task {
                                    await togglePickStatus(pickItem)
                                }
                            }
                        )
                        .disabled(updatingPickIds.contains(pickItem.id) || updatingSkuIds.contains(pickItem.sku?.id ?? ""))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                Task {
                                    await toggleCheeseStatus(pickItem)
                                }
                            } label: {
                                Label(pickItem.sku?.isCheeseAndCrackers == true ? "Remove Cheese" : "Add as Cheese", systemImage: pickItem.sku?.isCheeseAndCrackers == true ? "minus.circle" : "plus.circle")
                            }
                            .tint(pickItem.sku?.isCheeseAndCrackers == true ? .orange : .yellow)
                            
                            Button {
                                selectedPickItemForCountPointer = pickItem
                            } label: {
                                Label("Change Input Field", systemImage: "square.and.pencil")
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
        .sheet(isPresented: $showingChocolateBoxesSheet) {
            ChocolateBoxesSheet(viewModel: viewModel, locationMachines: machines)
                .presentationDetents([.fraction(0.5), .large])
                .presentationDragIndicator(.visible)
        }
        .onReceive(viewModel.$showingChocolateBoxesSheet) { showing in
            showingChocolateBoxesSheet = showing
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
                viewModel: viewModel
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
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
                        Task {
                            await resetLocationPickStatuses()
                        }
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
    }
    
    private func togglePickStatus(_ pickItem: RunDetail.PickItem) async {
        updatingPickIds.insert(pickItem.id)
        
        let newStatus = pickItem.isPicked ? "PENDING" : "PICKED"
        
        do {
            try await service.updatePickItemStatuses(
                runId: runId,
                pickIds: [pickItem.id],
                status: newStatus,
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
    
    private func toggleCheeseStatus(_ pickItem: RunDetail.PickItem) async {
        guard let skuId = pickItem.sku?.id else { return }
        
        updatingSkuIds.insert(skuId)
        
        let newCheeseStatus = !(pickItem.sku?.isCheeseAndCrackers ?? false)
        
        do {
            try await service.updateSkuCheeseStatus(
                skuId: skuId,
                isCheeseAndCrackers: newCheeseStatus,
                credentials: session.credentials
            )
            await onPickStatusChanged()
        } catch {
            // Handle error - could show an alert
            print("Failed to update SKU cheese status: \(error)")
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

struct CountPointerSelectionSheet: View {
    let pickItem: RunDetail.PickItem
    let onDismiss: () -> Void
    let onPointerSelected: (String) -> Void
    @ObservedObject var viewModel: RunDetailViewModel
    
    private let countPointers = [
        ("current", "Current", "Current inventory count"),
        ("par", "PAR", "Par level count"),
        ("need", "Need", "Needed count"),
        ("forecast", "Forecast", "Forecast count"),
        ("total", "Total", "Total count")
    ]
    
    private var currentSelection: String {
        // Find the updated pickItem from the refreshed data
        let updatedPickItem = viewModel.detail?.pickItems.first { $0.id == pickItem.id }
        return updatedPickItem?.sku?.countNeededPointer ?? pickItem.sku?.countNeededPointer ?? "total"
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(countPointers, id: \.0) { pointer in
                        CountPointerRow(
                            pointer: pointer,
                            currentCount: pickItem.countForPointer(pointer.0),
                            isSelected: pointer.0 == currentSelection
                        ) {
                            onPointerSelected(pointer.0)
                        }
                    }
                } header: {
                    Text("Select Count Source")
                } footer: {
                    Text("Choose which field determines the needed count for this item.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(pickItem.sku?.name ?? "Unknown SKU")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
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

    init(pickItem: RunDetail.PickItem, onToggle: @escaping () -> Void, showsLocation: Bool = false) {
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
            Button(action: onToggle) {
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(pickItem.sku?.name ?? "Unknown SKU")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if let skuType = pickItem.sku?.type {
                        if skuType != "General" {
                            Text("| \(skuType)")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .fontWeight(.semibold)
                        } else if let skuCode = pickItem.sku?.code {
                            Text(skuCode)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .fontWeight(.regular)
                        }
                    }
                }
                
                FlowLayout(spacing: 6) {
                    if showsLocation, let locationLabel {
                        detailChip("\(locationLabel)")
                    }
                    
                    if let machineCode = pickItem.machine?.description {
                        detailChip("Machine: \(machineCode)")
                    }
                    
                    detailChip("Coil: \(pickItem.coilItem.coil.code)")
                }
            }
            .padding(.vertical, 6)
            
            Spacer()
            
            Text("\(pickItem.count)")
                .font(.title)
                .fontDesign(.rounded)
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



#Preview {
    let location = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
    let machineType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
    let machineA = RunDetail.Machine(id: "machine-1", code: "A-01", description: "Lobby", machineType: machineType, location: location)
    let machineB = RunDetail.Machine(id: "machine-2", code: "B-12", description: "Breakroom", machineType: machineType, location: location)

    let coilA = RunDetail.Coil(id: "coil-1", code: "C1", machineId: machineA.id)
    let coilB = RunDetail.Coil(id: "coil-2", code: "C2", machineId: machineB.id)

    let coilItemA = RunDetail.CoilItem(id: "coil-item-1", par: 12, coil: coilA)
    let coilItemB = RunDetail.CoilItem(id: "coil-item-2", par: 8, coil: coilB)

    let sku = RunDetail.Sku(id: "sku-1", code: "SKU-001", name: "Trail Mix", type: "Snack", isCheeseAndCrackers: false, countNeededPointer: "total")

    let pickA = RunDetail.PickItem(id: "pick-1", count: 6, current: 8, par: 10, need: 6, forecast: 7, total: 12, status: "PICKED", pickedAt: Date(), coilItem: coilItemA, sku: sku, machine: machineA, location: location)
    let pickB = RunDetail.PickItem(id: "pick-2", count: 4, current: 3, par: 8, need: 4, forecast: 5, total: 9, status: "PENDING", pickedAt: nil, coilItem: coilItemB, sku: sku, machine: machineB, location: location)

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
        LocationDetailView(
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
