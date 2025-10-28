//
//  RunHistoryView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private struct RunSection: Identifiable {
    let date: Date
    let runs: [Run]

    var id: Date { date }
}

struct RunHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.haptics) private var haptics
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]
    @AppStorage("settings.webhookURL") private var webhookURL: String = ""
    @AppStorage("settings.apiKey") private var apiKey: String = ""
    @AppStorage("settings.email") private var userEmail: String = ""
    @StateObject private var mailIntegrationViewModel = MailIntegrationViewModel()

    @State private var runPendingDeletion: Run?
    @State private var isConfirmingDeletion = false
    @State private var isImportingCSV = false
    @State private var isMailSheetPresented = false
    @State private var importErrorMessage: String?

    private let csvImporter = CSVRunImporter()

    private var runSections: [RunSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: runs) { calendar.startOfDay(for: $0.date) }
        let sortedDates = grouped.keys.sorted(by: >)
        return sortedDates.map { date in
            let entries = (grouped[date] ?? []).sorted { $0.date > $1.date }
            return RunSection(date: date, runs: entries)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if runSections.isEmpty {
                    ContentUnavailableView("No runs yet",
                                            systemImage: "tray",
                                            description: Text("Import a CSV to start tracking runs."))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(runSections) { section in
                        Section(section.date.formatted(.dateTime.month().day().year())) {
                            ForEach(section.runs) { run in
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
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        runPendingDeletion = run
                                        isConfirmingDeletion = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            }
                        }
                    }
                }
            }
            .alert("Are you sure?", isPresented: $isConfirmingDeletion, presenting: runPendingDeletion) { run in
                Button("Delete", role: .destructive) {
                    haptics.destructiveActionTap()
                    delete(run: run)
                    runPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    haptics.secondaryButtonTap()
                    runPendingDeletion = nil
                }
            } message: { run in
                Text("Are you sure you want to delete this run from \(run.date.formatted(.dateTime.day().month().year()))?")
            }
            .navigationTitle("Runs")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        haptics.secondaryButtonTap()
                        isMailSheetPresented = true
                    } label: {
                        Label("Compose Email", systemImage: "envelope.badge.plus")
                    }

                    Button {
                        haptics.secondaryButtonTap()
                        isImportingCSV = true
                    } label: {
                        Label("Import Run", systemImage: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $isImportingCSV,
                          allowedContentTypes: [.commaSeparatedText, .folder],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                case .success(let urls):
                    importRun(from: urls)
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
                    haptics.secondaryButtonTap()
                    importErrorMessage = nil
                }
            } message: {
                Text(importErrorMessage ?? "")
            }
            .sheet(isPresented: $isMailSheetPresented) {
                MailIntegrationSheet(viewModel: mailIntegrationViewModel,
                                     webhookURL: webhookURL,
                                     apiKey: apiKey,
                                     recipientEmail: userEmail)
            }
        }
    }

    private func importRun(from selections: [URL]) {
        guard !selections.isEmpty else {
            importErrorMessage = "No files were selected."
            return
        }

        var securedURLs: [URL] = []
        securedURLs.reserveCapacity(selections.count)
        defer {
            securedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        }

        do {
            let csvFiles = try collectCSVFiles(from: selections, securedResources: &securedURLs)
            guard !csvFiles.isEmpty else {
                throw CSVImportError.noCSVFiles
            }

            var payloads: [CSVRunImporter.RunLocationPayload] = []
            payloads.reserveCapacity(csvFiles.count)

            for url in csvFiles {
                let payload = try csvImporter.loadLocation(from: url)
                payloads.append(payload)
            }

            try persistRun(using: payloads)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func persistRun(using payloads: [CSVRunImporter.RunLocationPayload]) throws {
        guard let first = payloads.first else { return }

        let storedName = UserDefaults.standard.string(forKey: "settings.username")
        let runnerName = (storedName?.isEmpty == false) ? storedName! : first.runner
        let runDate = payloads.map(\.date).min() ?? first.date
        let run = Run(id: UUID().uuidString, runner: runnerName, date: runDate)
        modelContext.insert(run)

        var machinesByID: [String: Machine] = [:]
        var itemsByID: [String: Item] = [:]
        var coilsByID: [String: Coil] = [:]

        var nextLocationOrder = 1

        for payload in payloads {
            let location = try upsertLocation(payload.location)
            let machineResults = try upsertMachines(payload.machines, location: location)
            machinesByID.merge(machineResults) { _, new in new }

            let itemResults = try upsertItems(payload.items)
            itemsByID.merge(itemResults) { _, new in new }

            let coilResults = try upsertCoils(payload.coils, machines: machinesByID, items: itemsByID)
            coilsByID.merge(coilResults) { _, new in new }

            var didCreateRunCoil = false
            for runCoilPayload in payload.runCoils {
                guard let coil = coilsByID[runCoilPayload.coilID] else {
                    continue
                }

                let runCoil = RunCoil(id: runCoilPayload.id,
                                      pick: runCoilPayload.pick,
                                      packOrder: Int64(nextLocationOrder),
                                      packed: false,
                                      run: run,
                                      coil: coil)
                modelContext.insert(runCoil)
                didCreateRunCoil = true

                if !run.runCoils.contains(where: { $0.id == runCoil.id }) {
                    run.runCoils.append(runCoil)
                }
                if !coil.runCoils.contains(where: { $0.id == runCoil.id }) {
                    coil.runCoils.append(runCoil)
                }
            }

            if didCreateRunCoil {
                nextLocationOrder += 1
            }
        }

        run.runCoils.sort { lhs, rhs in
            if lhs.packOrder == rhs.packOrder {
                return lhs.coil.machinePointer.localizedStandardCompare(rhs.coil.machinePointer) == .orderedAscending
            }
            return lhs.packOrder < rhs.packOrder
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
        let runnerName = run.runner.isEmpty ? "Unknown" : run.runner
        let locationNames = Set(run.runCoils.compactMap { $0.coil.machine.location?.name })
        if locationNames.count == 1, let name = locationNames.first {
            return "\(runnerName) - \(name)"
        }
        if locationNames.count > 1 {
            return "\(runnerName) - \(locationNames.count) locations"
        }
        return runnerName
    }

    private func runSubtitle(for run: Run) -> String {
        let machineIDs = Set(run.runCoils.map { $0.coil.machine.id })

        let machineCount = machineIDs.count
        let coilCount = Set(run.runCoils.map(\.coil.id)).count

        let machineText = "\(machineCount) \(machineCount == 1 ? "machine" : "machines")"
        let coilText = "\(coilCount) \(coilCount == 1 ? "coil" : "coils")"

        return "\(machineText) - \(coilText)"
    }
}

private enum CSVImportError: LocalizedError {
    case securityScope(String)
    case noCSVFiles

    var errorDescription: String? {
        switch self {
        case .securityScope(let name):
            return "Unable to access \(name)."
        case .noCSVFiles:
            return "No CSV files were found in the selected location."
        }
    }
}

extension RunHistoryView {
    private func collectCSVFiles(from selections: [URL],
                                 securedResources: inout [URL]) throws -> [URL] {
        var gatheredFiles: [URL] = []
        var seen: Set<URL> = []

        for selection in selections {
            let files = try collectCSVFiles(at: selection, securedResources: &securedResources)
            for file in files where seen.insert(file).inserted {
                gatheredFiles.append(file)
            }
        }

        gatheredFiles.sort { lhs, rhs in
            lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }
        return gatheredFiles
    }

    private func collectCSVFiles(at url: URL,
                                 securedResources: inout [URL]) throws -> [URL] {
        guard url.startAccessingSecurityScopedResource() else {
            throw CSVImportError.securityScope(url.lastPathComponent)
        }

        securedResources.append(url)

        if url.hasDirectoryPath {
            return try collectCSVFiles(inDirectory: url, securedResources: &securedResources)
        }

        if url.pathExtension.lowercased() == "csv" {
            return [url]
        }
        return []
    }

    private func collectCSVFiles(inDirectory directory: URL,
                                 securedResources: inout [URL]) throws -> [URL] {
        let manager = FileManager.default
        let enumerator = manager.enumerator(at: directory,
                                            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                                            options: [.skipsHiddenFiles])

        var files: [URL] = []

        while let next = enumerator?.nextObject() as? URL {
            let resourceValues = try next.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])

            if resourceValues.isDirectory == true {
                continue
            }

            guard resourceValues.isRegularFile == true else {
                continue
            }

            if next.pathExtension.lowercased() == "csv" {
                if next.startAccessingSecurityScopedResource() {
                    securedResources.append(next)
                    files.append(next)
                } else {
                    throw CSVImportError.securityScope(next.lastPathComponent)
                }
            }
        }

        return files
    }
}

#Preview {
    RunHistoryView()
        .modelContainer(PreviewFixtures.container)
}
