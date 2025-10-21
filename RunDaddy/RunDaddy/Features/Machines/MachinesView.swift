//
//  MachinesView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Charts
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
            return lhs.machinePointer.localizedStandardCompare(rhs.machinePointer) == .orderedAscending
        }
    }

    private func itemDescription(for coil: Coil) -> String {
        if coil.item.type.isEmpty {
            return coil.item.name
        }
        return "\(coil.item.name) - \(coil.item.type)"
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
                    NavigationLink {
                        CoilDetailView(coil: coil)
                    } label: {
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
        }
        .navigationTitle(machine.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CoilDetailView: View {
    @Bindable var coil: Coil

    private var history: [RunCoil] {
        coil.runCoils.sorted { lhs, rhs in
            lhs.run.date < rhs.run.date
        }
    }

    private var chartData: [CoilHistoryPoint] {
        history.map { runCoil in
            CoilHistoryPoint(date: runCoil.run.date,
                             pick: runCoil.pick,
                             packOrder: runCoil.packOrder,
                             runName: runCoil.run.runner.isEmpty ? runCoil.run.id : runCoil.run.runner)
        }
    }

    private var totalPick: Int64 {
        history.reduce(0) { $0 + $1.pick }
    }

    private var maxPick: Int64 {
        history.map(\.pick).max() ?? 0
    }

    private var averagePick: Double {
        guard !history.isEmpty else { return 0 }
        return Double(totalPick) / Double(history.count)
    }

    var body: some View {
        List {
            Section("Coil Info") {
                LabeledContent("Coil ID") { Text(coil.id) }
                LabeledContent("Machine") { Text(coil.machine.name) }
                LabeledContent("Item") { Text(coil.item.name) }
                LabeledContent("Item Type") { Text(coil.item.type) }
                LabeledContent("Item Code") { Text(coil.item.id) }
                LabeledContent("Stock Limit") { Text("\(coil.stockLimit)") }
            }

            Section("Pick History") {
                if history.isEmpty {
                    Text("This coil has not been used in any runs yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(chartData) { point in
                            LineMark(
                                x: .value("Run Date", point.date),
                                y: .value("Need", point.pick)
                            )
                            .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value("Run Date", point.date),
                                y: .value("Need", point.pick)
                            )
                        }
                    }
                    .frame(height: 220)
                    .chartYAxisLabel(position: .leading) {
                        Text("Need")
                    }
                    .chartXAxisLabel(position: .bottom) {
                        Text("Run Date")
                    }

                    HStack {
                        StatTile(title: "Total", value: "\(totalPick)")
                        StatTile(title: "Average", value: averagePick.formatted(.number.precision(.fractionLength(1))))
                        StatTile(title: "Max", value: "\(maxPick)")
                    }
                    .padding(.vertical, 4)
                }
            }

            if !history.isEmpty {
                Section("Runs") {
                    ForEach(history) { runCoil in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(runTitle(for: runCoil.run))
                                    .font(.headline)
                                Spacer()
                                Text(runCoil.run.date, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 16) {
                                LabeledValue(title: "Need", value: "\(runCoil.pick)")
                                LabeledValue(title: "Order", value: "\(runCoil.packOrder)")
                                LabeledValue(title: "Packed", value: runCoil.packed ? "Yes" : "No")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Coil \(coil.machinePointer)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runTitle(for run: Run) -> String {
        if !run.runner.isEmpty {
            return run.runner
        }
        return run.runCoils.first?.coil.machine.location?.name ?? run.id
    }
}

private struct CoilHistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let pick: Int64
    let packOrder: Int64
    let runName: String
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct LabeledValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

#Preview("Coil Detail") {
    NavigationStack {
        if let run = PreviewFixtures.sampleRunOptional,
           let coil = run.runCoils.first?.coil {
            CoilDetailView(coil: coil)
        } else {
            Text("Missing preview data")
        }
    }
    .modelContainer(PreviewFixtures.container)
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
