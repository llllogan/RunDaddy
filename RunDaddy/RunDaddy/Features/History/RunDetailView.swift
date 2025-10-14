//
//  RunDetailView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftData
import SwiftUI

fileprivate struct RunMachineSection: Identifiable {
    let machine: Machine
    let coils: [RunCoil]

    var id: String { machine.id }
    var coilCount: Int { coils.count }
}

fileprivate struct RunLocationSection: Identifiable {
    let location: Location
    let packOrder: Int
    let machines: [RunMachineSection]

    var id: String { location.id }
    var machineCount: Int { machines.count }
    var coilCount: Int { machines.reduce(into: 0) { $0 += $1.coilCount } }
}

struct RunDetailView: View {
    @Bindable var run: Run
    @State private var isPresentingOrderEditor = false

    private var locationSections: [RunLocationSection] {
        Self.locationSections(for: run)
    }

    fileprivate static func locationSections(for run: Run) -> [RunLocationSection] {
        var byLocation: [String: [RunCoil]] = [:]

        for runCoil in run.runCoils {
            guard let location = runCoil.coil.machine.location else { continue }
            byLocation[location.id, default: []].append(runCoil)
        }

        return byLocation.compactMap { _, runCoils in
            guard let location = runCoils.first?.coil.machine.location else { return nil }

            let machines = Dictionary(grouping: runCoils) { $0.coil.machine.id }
                .compactMap { _, machineCoils -> RunMachineSection? in
                    guard let machine = machineCoils.first?.coil.machine else { return nil }
                    let sortedCoils = machineCoils.sorted { lhs, rhs in
                        if lhs.packOrder == rhs.packOrder {
                            return lhs.coil.machinePointer < rhs.coil.machinePointer
                        }
                        return lhs.packOrder < rhs.packOrder
                    }
                    return RunMachineSection(machine: machine, coils: sortedCoils)
                }
                .sorted {
                    $0.machine.name.localizedCaseInsensitiveCompare($1.machine.name) == .orderedAscending
                }

            let locationOrder = runCoils.map { Int($0.packOrder) }.min() ?? Int.max
            let safeOrder = locationOrder == Int.max ? 0 : locationOrder
            return RunLocationSection(location: location,
                                      packOrder: safeOrder,
                                      machines: machines)
        }
        .sorted {
            if $0.packOrder == $1.packOrder {
                return $0.location.name.localizedCaseInsensitiveCompare($1.location.name) == .orderedAscending
            }
            return $0.packOrder < $1.packOrder
        }
    }

    private func applyLocationOrder(_ items: [LocationOrderEditor.Item]) {
        let orderMap = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset + 1) })

        withAnimation {
            for runCoil in run.runCoils {
                guard let locationID = runCoil.coil.machine.location?.id,
                      let newOrder = orderMap[locationID] else {
                    continue
                }
                runCoil.packOrder = Int64(newOrder)
            }

            run.runCoils.sort { lhs, rhs in
                if lhs.packOrder == rhs.packOrder {
                    return lhs.coil.machinePointer < rhs.coil.machinePointer
                }
                return lhs.packOrder < rhs.packOrder
            }
        }
    }

    private var locationCount: Int {
        locationSections.count
    }

    private var machineCount: Int {
        locationSections.reduce(into: 0) { $0 += $1.machineCount }
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
                LabeledContent("Locations") {
                    if locationCount == 1, let section = locationSections.first {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.location.name)
                            if !section.location.address.isEmpty {
                                Text(section.location.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("\(locationCount)")
                    }
                }
                LabeledContent("Machines") {
                    Text("\(machineCount)")
                }
                LabeledContent("Total Coils") {
                    Text("\(totalCoils)")
                }
            }

            Section("Locations") {
                if locationSections.isEmpty {
                    Text("No locations were imported for this run.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(locationSections) { section in
                        NavigationLink {
                            RunLocationDetailView(section: section)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Order \(section.packOrder)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(section.location.name)
                                    .font(.headline)
                                if !section.location.address.isEmpty {
                                    Text(section.location.address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(section.machineCount) \(section.machineCount == 1 ? "machine" : "machines") - \(section.coilCount) \(section.coilCount == 1 ? "coil" : "coils")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Reorder") {
                    isPresentingOrderEditor = true
                }
                .disabled(locationSections.count <= 1)
            }
        }
        .sheet(isPresented: $isPresentingOrderEditor) {
            let items = locationSections.map { section in
                LocationOrderEditor.Item(id: section.id,
                                         name: section.location.name,
                                         packOrder: section.packOrder)
            }
            LocationOrderEditor(items: items) { updatedItems in
                applyLocationOrder(updatedItems)
            }
        }
    }
}

fileprivate struct RunLocationDetailView: View {
    let section: RunLocationSection

    var body: some View {
        List {
            Section("Location Details") {
                LabeledContent("Order") {
                    Text("\(section.packOrder)")
                }
                LabeledContent("Name") {
                    Text(section.location.name)
                }
                if !section.location.address.isEmpty {
                    LabeledContent("Address") {
                        Text(section.location.address)
                    }
                }
                LabeledContent("Machines") {
                    Text("\(section.machineCount)")
                }
                LabeledContent("Total Coils") {
                    Text("\(section.coilCount)")
                }
            }

            ForEach(section.machines) { machineSection in
                Section(machineSection.machine.name) {
                    ForEach(machineSection.coils) { runCoil in
                        CoilRow(runCoil: runCoil)
                    }
                }
            }
        }
        .navigationTitle(section.location.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

fileprivate struct CoilRow: View {
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
        HStack(alignment: .center, spacing: 16) {
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
            labelValue(title: "Need", value: runCoil.pick)
        }
        .padding(.vertical, 2)
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

fileprivate struct LocationOrderEditor: View {
    struct Item: Identifiable, Equatable {
        let id: String
        let name: String
        var packOrder: Int
    }

    @Environment(\.dismiss) private var dismiss
    @State private var items: [Item]
    private let onSave: ([Item]) -> Void

    init(items: [Item], onSave: @escaping ([Item]) -> Void) {
        let sorted = items.sorted { lhs, rhs in
            if lhs.packOrder == rhs.packOrder {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.packOrder < rhs.packOrder
        }
        _items = State(initialValue: sorted)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        Text(item.name)
                    }
                }
                .onMove { indices, newOffset in
                    items.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .navigationTitle("Reorder Locations")
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                }
            }
        }
    }

    private func saveAndDismiss() {
        var updated = items
        for index in updated.indices {
            updated[index].packOrder = index + 1
        }
        onSave(updated)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        RunDetailView(run: PreviewFixtures.sampleRun)
    }
    .modelContainer(PreviewFixtures.container)
}

#Preview("Location Detail") {
    NavigationStack {
        if let locationSection = RunDetailView.locationSections(for: PreviewFixtures.sampleRun).first {
            RunLocationDetailView(section: locationSection)
        } else {
            Text("Missing preview data")
        }
    }
    .modelContainer(PreviewFixtures.container)
}
