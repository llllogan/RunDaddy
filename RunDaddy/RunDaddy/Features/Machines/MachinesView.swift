//
//  MachinesView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftData
import SwiftUI

struct MachinesView: View {
    @Query(sort: \Location.name, order: .forward) private var locations: [Location]

    var body: some View {
        NavigationStack {
            Group {
                if locations.isEmpty {
                    ContentUnavailableView("No Locations Yet",
                                           systemImage: "building.2",
                                           description: Text("Import a run to see locations, machines, and coils here."))
                } else {
                    List {
                        ForEach(locations) { location in
                            NavigationLink {
                                LocationMachinesView(location: location)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(location.name)
                                        .font(.headline)
                                    if !location.address.isEmpty {
                                        Text(location.address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !location.machines.isEmpty {
                                        Text("\(location.machines.count) \(location.machines.count == 1 ? "machine" : "machines")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Locations")
        }
    }
}

private struct LocationMachinesView: View {
    let location: Location
    private let machines: [Machine]

    init(location: Location) {
        self.location = location
        self.machines = location.machines.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if machines.isEmpty {
                ContentUnavailableView("No Machines",
                                       systemImage: "gearshape.2",
                                       description: Text("There are no machines recorded for this location yet."))
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .listRowBackground(Color(.systemGroupedBackground))
            } else {
                ForEach(machines) { machine in
                    NavigationLink {
                        MachineCoilsView(machine: machine)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(machine.name)
                                .font(.headline)
                            if let label = machine.locationLabel, !label.isEmpty {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(machine.coils.count) \(machine.coils.count == 1 ? "coil" : "coils")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(location.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MachineCoilsView: View {
    @Bindable var machine: Machine

    private var coils: [Coil] {
        machine.coils.sorted { lhs, rhs in
            if lhs.machinePointer == rhs.machinePointer {
                return lhs.id < rhs.id
            }
            return lhs.machinePointer < rhs.machinePointer
        }
    }

    private func itemDescription(for coil: Coil) -> String {
        if coil.item.type.isEmpty {
            return coil.item.name
        }
        return "\(coil.item.type) - \(coil.item.name)"
    }

    var body: some View {
        List {
            if coils.isEmpty {
                ContentUnavailableView("No Coils",
                                       systemImage: "shippingbox",
                                       description: Text("This machine does not have any coils yet."))
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .listRowBackground(Color(.systemGroupedBackground))
            } else {
                ForEach(coils) { coil in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Coil \(coil.machinePointer)")
                                .font(.headline)
                            Spacer()
                            Text("ID \(coil.id)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(coil.item.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(itemDescription(for: coil))
                            .font(.subheadline)
                        Text("Stock limit \(coil.stockLimit)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(machine.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Locations") {
    NavigationStack {
        MachinesView()
    }
    .modelContainer(PreviewFixtures.container)
}

#Preview("Machines") {
    NavigationStack {
        if let run = PreviewFixtures.sampleRunOptional,
           let location = run.runCoils.first?.coil.machine.location {
            LocationMachinesView(location: location)
        } else {
            Text("Missing preview data")
        }
    }
}

#Preview("Coils") {
    NavigationStack {
        if let run = PreviewFixtures.sampleRunOptional,
           let machine = run.runCoils.first?.coil.machine {
            MachineCoilsView(machine: machine)
        } else {
            Text("Missing preview data")
        }
    }
}
