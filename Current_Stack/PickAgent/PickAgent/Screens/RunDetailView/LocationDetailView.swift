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
    let onPickStatusChanged: () -> Void
    
    @State private var selectedMachineFilter: String?
    @State private var coilSortOrder: CoilSortOrder = .descending
    @State private var updatingPickIds: Set<String> = []
    @State private var showingChocolateBoxesSheet = false

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
                LocationOverviewBento(summary: overviewSummary, machines: machines, viewModel: viewModel, onChocolateBoxesTap: {
                    showingChocolateBoxesSheet = true
                })
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
                        .disabled(updatingPickIds.contains(pickItem.id))
                    }
                }
            } header: {
                Text("Picks")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(detail.section.title)
        .sheet(isPresented: $showingChocolateBoxesSheet) {
            ChocolateBoxesSheet(viewModel: viewModel)
        }
        .onReceive(viewModel.$showingChocolateBoxesSheet) { showing in
            showingChocolateBoxesSheet = showing
        }
    }
    
    private func togglePickStatus(_ pickItem: RunDetail.PickItem) async {
        updatingPickIds.insert(pickItem.id)
        
        let newStatus = pickItem.isPicked ? "PENDING" : "PICKED"
        
        do {
            try await service.updatePickItemStatus(
                runId: runId,
                pickId: pickItem.id,
                status: newStatus,
                credentials: session.credentials
            )
            await MainActor.run {
                onPickStatusChanged()
            }
        } catch {
            // Handle error - could show an alert
            print("Failed to update pick status: \(error)")
        }
        
        _ = await MainActor.run {
            updatingPickIds.remove(pickItem.id)
        }
    }
}

private struct PickEntryRow: View {
    let pickItem: RunDetail.PickItem
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(pickItem.isPicked ? Color.green : Color.gray, lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white))
                    
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
                    
                    if let skuCode = pickItem.sku?.code {
                        Text(skuCode)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .fontWeight(.regular)
                    }
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let machineCode = pickItem.machine?.code {
                        Text("Machine: \(machineCode)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    
                    Text("Coil: \(pickItem.coilItem.coil.code)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 6)
            
            Spacer()
            
            Text("\(pickItem.count)")
                .font(.title)
        }
    }
}

struct PreviewRunsService: RunsServicing {
    func fetchRuns(for schedule: RunsSchedule, credentials: AuthCredentials) async throws -> [RunSummary] {
        []
    }

    func fetchRunDetail(withId runId: String, credentials: AuthCredentials) async throws -> RunDetail {
        let location = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
        let machineType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
        let machineA = RunDetail.Machine(id: "machine-1", code: "A-01", description: "Lobby", machineType: machineType, location: location)
        let machineB = RunDetail.Machine(id: "machine-2", code: "B-12", description: "Breakroom", machineType: machineType, location: location)

        let coilA = RunDetail.Coil(id: "coil-1", code: "C1", machineId: machineA.id)
        let coilB = RunDetail.Coil(id: "coil-2", code: "C2", machineId: machineB.id)

        let coilItemA = RunDetail.CoilItem(id: "coil-item-1", par: 12, coil: coilA)
        let coilItemB = RunDetail.CoilItem(id: "coil-item-2", par: 8, coil: coilB)

        let sku = RunDetail.Sku(id: "sku-1", code: "SKU-001", name: "Trail Mix", type: "Snack", isCheeseAndCrackers: false)

        let pickA = RunDetail.PickItem(id: "pick-1", count: 6, status: "PICKED", pickedAt: Date(), coilItem: coilItemA, sku: sku, machine: machineA, location: location)
        let pickB = RunDetail.PickItem(id: "pick-2", count: 4, status: "PENDING", pickedAt: nil, coilItem: coilItemB, sku: sku, machine: machineB, location: location)

        return RunDetail(
            id: "run-1",
            status: "PICKING",
            companyId: "company-1",
            scheduledFor: Date(),
            pickingStartedAt: Date().addingTimeInterval(-3600),
            pickingEndedAt: nil,
            createdAt: Date().addingTimeInterval(-7200),
            picker: nil,
            runner: nil,
            locations: [location],
            machines: [machineA, machineB],
            pickItems: [pickA, pickB],
            chocolateBoxes: []
        )
    }

    func assignUser(to runId: String, userId: String, role: String, credentials: AuthCredentials) async throws {
        // Preview does nothing
    }
    
    func fetchCompanyUsers(credentials: AuthCredentials) async throws -> [CompanyUser] {
        []
    }
    
    func updatePickItemStatus(runId: String, pickId: String, status: String, credentials: AuthCredentials) async throws {
        // Preview does nothing
    }
    
    func fetchChocolateBoxes(for runId: String, credentials: AuthCredentials) async throws -> [RunDetail.ChocolateBox] {
        let location = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
        let machineType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
        let machineA = RunDetail.Machine(id: "machine-1", code: "A-01", description: "Lobby", machineType: machineType, location: location)
        
        let chocolateBox1 = RunDetail.ChocolateBox(id: "box-1", number: 1, machine: machineA)
        let chocolateBox2 = RunDetail.ChocolateBox(id: "box-2", number: 34, machine: machineA)
        let chocolateBox3 = RunDetail.ChocolateBox(id: "box-3", number: 5, machine: nil)
        
        return [chocolateBox1, chocolateBox2, chocolateBox3]
    }
    
    func createChocolateBox(for runId: String, number: Int, machineId: String, credentials: AuthCredentials) async throws -> RunDetail.ChocolateBox {
        let location = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
        let machineType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
        let machineA = RunDetail.Machine(id: machineId, code: "A-01", description: "Lobby", machineType: machineType, location: location)
        
        return RunDetail.ChocolateBox(id: "new-box", number: number, machine: machineA)
    }
    
    func updateChocolateBox(for runId: String, boxId: String, number: Int?, machineId: String?, credentials: AuthCredentials) async throws -> RunDetail.ChocolateBox {
        let location = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
        let machineType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
        let machineA = RunDetail.Machine(id: machineId ?? "machine-1", code: "A-01", description: "Lobby", machineType: machineType, location: location)
        
        return RunDetail.ChocolateBox(id: boxId, number: number ?? 1, machine: machineA)
    }
    
    func deleteChocolateBox(for runId: String, boxId: String, credentials: AuthCredentials) async throws {
        // Preview does nothing
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

    let sku = RunDetail.Sku(id: "sku-1", code: "SKU-001", name: "Trail Mix", type: "Snack", isCheeseAndCrackers: false)

    let pickA = RunDetail.PickItem(id: "pick-1", count: 6, status: "PICKED", pickedAt: Date(), coilItem: coilItemA, sku: sku, machine: machineA, location: location)
    let pickB = RunDetail.PickItem(id: "pick-2", count: 4, status: "PENDING", pickedAt: nil, coilItem: coilItemB, sku: sku, machine: machineB, location: location)

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
