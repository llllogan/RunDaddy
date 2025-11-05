//
//  LocationDetailView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/26/2025.
//

import SwiftUI

struct LocationDetailView: View {
    let detail: RunLocationDetail
    @State private var selectedMachineFilter: String?

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
        if let machineId = selectedMachineFilter {
            return allPickItems.filter { $0.machine?.id == machineId }
        }
        return allPickItems
    }

    var body: some View {
        List {
            Section {
                LocationOverviewBento(summary: overviewSummary, machines: machines)
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
                }
                
                if filteredPickItems.isEmpty {
                    Text("No picks found.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(filteredPickItems, id: \.id) { pickItem in
                        PickEntryRow(pickItem: pickItem)
                    }
                }
            } header: {
                Text("Picks")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(detail.section.title)
    }
}

private struct PickEntryRow: View {
    let pickItem: RunDetail.PickItem

    var body: some View {
        HStack {
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

    return NavigationStack {
        LocationDetailView(detail: detail)
    }
}
