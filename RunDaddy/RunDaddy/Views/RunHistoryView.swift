//
//  RunHistoryView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI
import SwiftData

struct RunHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Run.name, order: .forward) private var runs: [Run]

    @State private var isPresentingNewRunSheet = false

    var body: some View {
        NavigationStack {
            List(runs) { run in
                Text(run.name)
            }
            .navigationTitle("Runs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresentingNewRunSheet = true
                    } label: {
                        Label("Add Run", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingNewRunSheet) {
                NewRunSheet { name in
                    addRun(named: name)
                }
            }
        }
    }

    private func addRun(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let run = Run(name: trimmedName)
        modelContext.insert(run)
    }
}

private struct NewRunSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @FocusState private var nameFieldFocused: Bool

    var onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Run name", text: $name)
                        .focused($nameFieldFocused)
                }
            }
            .navigationTitle("New Run")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                nameFieldFocused = true
            }
        }
    }
}

#Preview {
    RunHistoryView()
        .modelContainer(for: [Run.self, InventoryItem.self], inMemory: true)
}
