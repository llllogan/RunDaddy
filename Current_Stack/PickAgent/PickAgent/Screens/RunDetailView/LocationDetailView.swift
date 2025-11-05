//
//  LocationDetailView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/26/2025.
//

import SwiftUI

struct LocationDetailView: View {
    let detail: RunLocationDetail

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

            Section("Machines") {
                if machines.isEmpty {
                    Text("No machines assigned to this location yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(machines, id: \.id) { machine in
                        MachineSummaryRow(machine: machine, pickItems: detail.pickItems(for: machine))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(detail.section.title)
    }
}

private struct MachineSummaryRow: View {
    let machine: RunDetail.Machine
    let pickItems: [RunDetail.PickItem]

    private var packedCount: Int {
        pickItems.reduce(into: 0) { result, item in
            if item.isPicked {
                result += 1
            }
        }
    }

    private var remainingCount: Int {
        max(pickItems.count - packedCount, 0)
    }

    private var totalItemCount: Int {
        pickItems.reduce(0) { $0 + max($1.count, 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(machine.code)
                    .font(.headline)
                    .fontWeight(.semibold)

                if let typeName = machine.machineType?.name {
                    Text(typeName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
            }

            if let description = machine.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label("\(pickItems.count) coils", systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if totalItemCount > 0 {
                    Label("\(totalItemCount) items", systemImage: "cube")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if packedCount > 0 {
                    Label("\(packedCount) packed", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if remainingCount > 0 {
                    Label("\(remainingCount) remaining", systemImage: "cart")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 6)
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
