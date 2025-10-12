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
    @Query(sort: \Run.name, order: .forward) private var runs: [Run]

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
                        Text(run.name)
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
                Text("Are you sure you want to delete \"\(run.name)\"?")
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
        let runName = payload.name
        let descriptor = FetchDescriptor<Run>(predicate: #Predicate<Run> { run in
            run.name == runName
        })
        let existingRun = try modelContext.fetch(descriptor).first

        withAnimation {
            if let existingRun {
                modelContext.delete(existingRun)
            }

            let run = Run(name: payload.name)
            modelContext.insert(run)

            for item in payload.items {
                let inventoryItem = InventoryItem(code: item.code,
                                                  name: item.name,
                                                  count: item.count,
                                                  category: item.category,
                                                  checked: item.checked,
                                                  dateAdded: item.dateAdded,
                                                  dateChecked: item.dateChecked,
                                                  run: run)
                modelContext.insert(inventoryItem)
            }
        }
    }

    private func delete(run: Run) {
        withAnimation {
            modelContext.delete(run)
        }
    }
}

#Preview {
    RunHistoryView()
        .modelContainer(for: [Run.self, InventoryItem.self], inMemory: true)
}
