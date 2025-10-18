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

fileprivate func formattedOrderDescription(for packOrder: Int) -> String {
    guard packOrder > 0 else { return "Unscheduled" }
    if packOrder == 1 {
        return "1 (deliver last)"
    }
    return "\(packOrder)"
}

struct RunDetailView: View {
    @Bindable var run: Run
    @EnvironmentObject private var sessionController: PackingSessionController
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

    private var packedCount: Int {
        run.runCoils.filter(\.packed).count
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
                LabeledContent("Packed") {
                    Text("\(packedCount) / \(totalCoils)")
                }
            }

            Section("Locations") {
                if locationSections.isEmpty {
                    Text("No locations were imported for this run.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(locationSections) { section in
                        NavigationLink {
                            RunLocationDetailView(run: run, section: section)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Order \(formattedOrderDescription(for: section.packOrder))")
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
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    isPresentingOrderEditor = true
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .disabled(locationSections.count <= 1)
                .accessibilityLabel("Reorder locations")

                Button {
                    sessionController.beginSession(for: run)
                } label: {
                    Image(systemName: "tray.2")
                }
                .disabled(run.runCoils.isEmpty)
                .accessibilityLabel("Start packing session")
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
    @EnvironmentObject private var sessionController: PackingSessionController
    let run: Run
    let section: RunLocationSection

    private var locationRunCoils: [RunCoil] {
        section.machines.flatMap(\.coils)
    }

    private var hasPackedItems: Bool {
        locationRunCoils.contains(where: \.packed)
    }

    var body: some View {
        List {
            Section("Location Details") {
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
                LabeledContent("Order") {
                    Text(formattedOrderDescription(for: section.packOrder))
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
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    sessionController.beginSession(for: run)
                } label: {
                    Image(systemName: "tray.2")
                }
                .disabled(locationRunCoils.isEmpty)
                .accessibilityLabel("Start packing session")

                Menu {
                    Button {
                        markAllItemsAsUnpacked()
                    } label: {
                        Label("Mark All Unpacked", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!hasPackedItems)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(locationRunCoils.isEmpty)
                .accessibilityLabel("Location actions")
            }
        }
    }

    private func markAllItemsAsUnpacked() {
        guard hasPackedItems else { return }
        withAnimation {
            for runCoil in locationRunCoils {
                runCoil.packed = false
            }
        }
    }
}

fileprivate struct CoilRow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionController: PackingSessionController
    @Bindable var runCoil: RunCoil
    @State private var presentedAlert: AlertKind?
    @State private var pendingPackedValue: Bool = false

    private var coil: Coil { runCoil.coil }
    private var item: Item { coil.item }
    private var machine: Machine { coil.machine }

    private var itemDescriptor: String {
        if item.type.isEmpty {
            return item.name
        }
        return "\(item.type) - \(item.name)"
    }

    private var isAnnouncing: Bool {
        guard let session = sessionController.activeSession,
              session.run.id == runCoil.run.id else {
            return false
        }
        let viewModel = session.viewModel
        guard viewModel.isSessionRunning else { return false }
        return viewModel.currentRunCoilID == runCoil.id
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            toggleButton
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
        .swipeActions(edge: .leading) {
            Button(role: .destructive) {
                presentedAlert = .delete
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert(item: $presentedAlert) { kind in
            switch kind {
            case .delete:
                return Alert(title: Text("Remove Item?"),
                             message: Text("Are you sure you want to remove \(itemDescriptor) from this run?"),
                             primaryButton: .destructive(Text("Delete"), action: deleteRunCoil),
                             secondaryButton: .cancel(Text("Cancel")))
            case .sessionRestart:
                return Alert(title: Text("Packing Session Active"),
                             message: Text("To manually check this item off, your packing session has to be stopped and restarted, continue?"),
                             primaryButton: .cancel(Text("No")),
                             secondaryButton: .default(Text("Continue"), action: handleSessionRestartContinue))
            }
        }
    }

    private var toggleButton: some View {
        Button {
            handleToggleTap()
        } label: {
            ZStack {
                Image(systemName: runCoil.packed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(runCoil.packed ? Color.green : Color(.tertiaryLabel))
                    .opacity(isAnnouncing ? 0 : 1)
                if isAnnouncing {
                    Image(systemName: "speaker.wave.2.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.title3.weight(.semibold))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(runCoil.packed ? "Mark as unpacked" : "Mark as packed")
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

    private var isSessionRunningForRun: Bool {
        guard let session = sessionController.activeSession,
              session.run.id == runCoil.run.id else {
            return false
        }
        return session.viewModel.isSessionRunning
    }

    private func handleToggleTap() {
        let newValue = !runCoil.packed
        if newValue && isSessionRunningForRun {
            pendingPackedValue = newValue
            presentedAlert = .sessionRestart
        } else {
            applyToggle(newValue)
        }
    }

    private func applyToggle(_ newValue: Bool) {
        withAnimation {
            runCoil.packed = newValue
        }
    }

    private func deleteRunCoil() {
        let run = runCoil.run
        let identifier = runCoil.id
        if isAnnouncing {
            sessionController.activeSession?.viewModel.stepForward()
        }
        withAnimation {
            if let index = run.runCoils.firstIndex(where: { $0.id == identifier }) {
                run.runCoils.remove(at: index)
            }
            modelContext.delete(runCoil)
        }
        presentedAlert = nil
    }

    private func handleSessionRestartContinue() {
        guard isSessionRunningForRun else {
            applyToggle(pendingPackedValue)
            presentedAlert = nil
            pendingPackedValue = false
            return
        }
        let run = runCoil.run
        applyToggle(pendingPackedValue)
        sessionController.endSession()
        sessionController.beginSession(for: run)
        presentedAlert = nil
        pendingPackedValue = false
    }

    private enum AlertKind: Identifiable {
        case delete
        case sessionRestart

        var id: Int {
            switch self {
            case .delete: return 0
            case .sessionRestart: return 1
            }
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
    .environmentObject(PackingSessionController())
    .modelContainer(PreviewFixtures.container)
}

#Preview("Location Detail") {
    NavigationStack {
        if let locationSection = RunDetailView.locationSections(for: PreviewFixtures.sampleRun).first {
            RunLocationDetailView(run: PreviewFixtures.sampleRun, section: locationSection)
        } else {
            Text("Missing preview data")
        }
    }
    .environmentObject(PackingSessionController())
    .modelContainer(PreviewFixtures.container)
}
