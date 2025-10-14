//
//  RunHistoryView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RunHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]

    @State private var runPendingDeletion: Run?
    @State private var isConfirmingDeletion = false
    @State private var isImportingCSV = false
    @State private var importErrorMessage: String?

    private let csvImporter = CSVRunImporter()

    var body: some View {
        NavigationStack {
            List {
                ForEach(runs) { run in
                    NavigationLink {
                        RunDetailView(run: run)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(runTitle(for: run))
                                .font(.headline)
                            Text(runSubtitle(for: run))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            runPendingDeletion = run
                            isConfirmingDeletion = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .alert("Delete Run?", isPresented: $isConfirmingDeletion, presenting: runPendingDeletion) { run in
                Button("Delete", role: .destructive) {
                    delete(run: run)
                    runPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    runPendingDeletion = nil
                }
            } message: { run in
                Text("Are you sure you want to delete this run from \(run.date.formatted(.dateTime.day().month().year()))?")
            }
            .navigationTitle("Runs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isImportingCSV = true
                    } label: {
                        Label("Import Run", systemImage: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $isImportingCSV, allowedContentTypes: [.commaSeparatedText]) { result in
                switch result {
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                case .success(let url):
                    importRun(from: url)
                }
            }
            .alert("Import Failed", isPresented: Binding(get: {
                importErrorMessage != nil
            }, set: { newValue in
                if !newValue {
                    importErrorMessage = nil
                }
            })) {
                Button("OK", role: .cancel) {
                    importErrorMessage = nil
                }
            } message: {
                Text(importErrorMessage ?? "")
            }
        }
    }

    private func importRun(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importErrorMessage = "Unable to access the selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let payload = try csvImporter.loadRun(from: url)
            try persistRun(payload)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func persistRun(_ payload: CSVRunImporter.RunPayload) throws {
        let location = try upsertLocation(payload.location)
        let machines = try upsertMachines(payload.machines, location: location)
        let items = try upsertItems(payload.items)
        let coils = try upsertCoils(payload.coils, machines: machines, items: items)

        let run = Run(id: payload.runID, runner: payload.runner, date: payload.date)
        modelContext.insert(run)

        for payload in payload.runCoils {
            guard let coil = coils[payload.coilID] else { continue }

            let runCoil = RunCoil(id: payload.id,
                                  pick: payload.pick,
                                  packOrder: payload.packOrder,
                                  run: run,
                                  coil: coil)
            modelContext.insert(runCoil)
            if !run.runCoils.contains(where: { $0.id == runCoil.id }) {
                run.runCoils.append(runCoil)
            }
            if !coil.runCoils.contains(where: { $0.id == runCoil.id }) {
                coil.runCoils.append(runCoil)
            }
        }
    }

    private func upsertLocation(_ payload: CSVRunImporter.LocationPayload) throws -> Location {
        let locationID = payload.id
        let descriptor = FetchDescriptor<Location>(predicate: #Predicate<Location> { $0.id == locationID })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.name = payload.name
            existing.address = payload.address
            return existing
        }

        let location = Location(id: payload.id,
                                name: payload.name,
                                address: payload.address)
        modelContext.insert(location)
        return location
    }

    private func upsertMachines(_ payloads: [CSVRunImporter.MachinePayload],
                                location: Location) throws -> [String: Machine] {
        var results: [String: Machine] = [:]

        for payload in payloads {
            let machineID = payload.id
            let descriptor = FetchDescriptor<Machine>(predicate: #Predicate<Machine> { $0.id == machineID })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.name = payload.name
                existing.locationLabel = payload.locationLabel
                existing.location = location
                if !location.machines.contains(where: { $0.id == existing.id }) {
                    location.machines.append(existing)
                }
                results[payload.id] = existing
            } else {
                let machine = Machine(id: payload.id,
                                      name: payload.name,
                                      locationLabel: payload.locationLabel,
                                      location: location)
                modelContext.insert(machine)
                if !location.machines.contains(where: { $0.id == machine.id }) {
                    location.machines.append(machine)
                }
                results[payload.id] = machine
            }
        }

        return results
    }

    private func upsertItems(_ payloads: [CSVRunImporter.ItemPayload]) throws -> [String: Item] {
        var results: [String: Item] = [:]

        for payload in payloads {
            let itemID = payload.id
            let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.id == itemID })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.name = payload.name
                existing.type = payload.type
                results[payload.id] = existing
            } else {
                let item = Item(id: payload.id, name: payload.name, type: payload.type)
                modelContext.insert(item)
                results[payload.id] = item
            }
        }

        return results
    }

    private func upsertCoils(_ payloads: [CSVRunImporter.CoilPayload],
                             machines: [String: Machine],
                             items: [String: Item]) throws -> [String: Coil] {
        var results: [String: Coil] = [:]

        for payload in payloads {
            guard let machine = machines[payload.machineID],
                  let item = items[payload.itemID] else {
                continue
            }

            let coilID = payload.id
            let descriptor = FetchDescriptor<Coil>(predicate: #Predicate<Coil> { $0.id == coilID })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.machinePointer = payload.machinePointer
                existing.stockLimit = payload.stockLimit
                existing.machine = machine
                existing.item = item
                if !machine.coils.contains(where: { $0.id == existing.id }) {
                    machine.coils.append(existing)
                }
                results[payload.id] = existing
            } else {
                let coil = Coil(id: payload.id,
                                machinePointer: payload.machinePointer,
                                stockLimit: payload.stockLimit,
                                machine: machine,
                                item: item)
                modelContext.insert(coil)
                if !machine.coils.contains(where: { $0.id == coil.id }) {
                    machine.coils.append(coil)
                }
                results[payload.id] = coil
            }
        }

        return results
    }

    private func delete(run: Run) {
        withAnimation {
            modelContext.delete(run)
        }
    }

    private func runTitle(for run: Run) -> String {
        let dateText = run.date.formatted(.dateTime.day().month().year())
        if let location = run.runCoils.first?.coil.machine.location?.name, !location.isEmpty {
            return "\(location) - \(dateText)"
        }
        return dateText
    }

    private func runSubtitle(for run: Run) -> String {
        let machineIDs = Set(run.runCoils.compactMap { $0.coil.machine.id })
        let machineText = machineIDs.isEmpty ? "No machines" : "\(machineIDs.count) machines"
        if run.runner.isEmpty {
            return machineText
        }
        return "\(run.runner) - \(machineText)"
    }
}

#Preview {
    RunHistoryView()
        .modelContainer(PreviewFixtures.container)
}
