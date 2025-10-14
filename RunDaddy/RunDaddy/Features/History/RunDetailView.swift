//
//  RunDetailView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftData
import SwiftUI

struct RunDetailView: View {
    @Bindable var run: Run

    private struct MachineSection: Identifiable {
        let id: String
        let machine: Machine
        let coils: [RunCoil]
    }

    private var machineSections: [MachineSection] {
        var grouped: [String: [RunCoil]] = [:]

        for runCoil in run.runCoils {
            let machineID = runCoil.coil.machine.id
            grouped[machineID, default: []].append(runCoil)
        }

        return grouped.compactMap { key, value in
            guard let machine = value.first?.coil.machine else { return nil }
            let sorted = value.sorted { lhs, rhs in
                if lhs.packOrder == rhs.packOrder {
                    return lhs.coil.machinePointer < rhs.coil.machinePointer
                }
                return lhs.packOrder < rhs.packOrder
            }
            return MachineSection(id: key, machine: machine, coils: sorted)
        }
        .sorted { lhs, rhs in
            lhs.machine.name.localizedCaseInsensitiveCompare(rhs.machine.name) == .orderedAscending
        }
    }

    private var locationName: String {
        run.runCoils.first?.coil.machine.location?.name ?? "Unknown Location"
    }

    private var locationAddress: String {
        run.runCoils.first?.coil.machine.location?.address ?? ""
    }

    private var machineCount: Int {
        Set(run.runCoils.map { $0.coil.machine.id }).count
    }

    private var totalCoils: Int {
        run.runCoils.count
    }

    private var navigationTitle: String {
        run.date.formatted(.dateTime.day().month().year())
    }

    var body: some View {
        List {
            Section("Run Details") {
                LabeledContent("Date") {
                    Text(run.date.formatted(.dateTime.day().month().year()))
                }
                if !run.runner.isEmpty {
                    LabeledContent("Runner") {
                        Text(run.runner)
                    }
                }
                LabeledContent("Location") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(locationName)
                        if !locationAddress.isEmpty {
                            Text(locationAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Machines") {
                    Text("\(machineCount)")
                }
                LabeledContent("Total Coils") {
                    Text("\(totalCoils)")
                }
            }

            ForEach(machineSections) { section in
                Section(section.machine.name) {
                    ForEach(section.coils) { runCoil in
                        CoilRow(runCoil: runCoil)
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CoilRow: View {
    let runCoil: RunCoil

    private var coil: Coil { runCoil.coil }
    private var item: Item { coil.item }
    private var machine: Machine { coil.machine }

    private var itemDescriptor: String {
        if item.type.isEmpty {
            return item.name
        }
        return "\(item.type) - \(item.name)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(itemDescriptor)
                    .font(.headline)
                Text("Machine \(machine.id) - Coil \(coil.machinePointer)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                labelValue(title: "Need", value: runCoil.pick)
                labelValue(title: "Par", value: coil.stockLimit)
                labelValue(title: "Order", value: runCoil.packOrder)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func labelValue(title: String, value: Int64) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.subheadline)
                .bold()
        }
    }
}

#Preview {
    NavigationStack {
        RunDetailView(run: PreviewFixtures.sampleRun)
    }
    .modelContainer(PreviewFixtures.container)
}
