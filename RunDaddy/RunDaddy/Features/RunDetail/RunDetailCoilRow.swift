//
//  RunDetailCoilRow.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftData
import SwiftUI

struct CoilRow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionController: PackingSessionController
    @Environment(\.haptics) private var haptics
    @Bindable var runCoil: RunCoil
    @State private var isDeleteConfirmationPresented = false
    @State private var isSessionRestartAlertPresented = false
    @State private var pendingPackedValue: Bool = false

    private var coil: Coil { runCoil.coil }
    private var item: Item { coil.item }
    private var machine: Machine { coil.machine }

    private var itemDescriptor: String {
        if item.type.isEmpty {
            return item.name
        }
        return "\(item.name) - \(item.type)"
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
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                isDeleteConfirmationPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .confirmationDialog("Remove Item?",
                            isPresented: $isDeleteConfirmationPresented,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteRunCoil()
            }
            Button("Cancel") { }
        } message: {
            Text("Are you sure you want to remove \(itemDescriptor) from this run?")
        }
        .alert("Packing Session Active",
               isPresented: $isSessionRestartAlertPresented) {
            Button("No", role: .cancel) {
                pendingPackedValue = false
            }
            Button("Continue") {
                handleSessionRestartContinue()
            }
        } message: {
            Text("To manually check this item off, your packing session has to be stopped and restarted, continue?")
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
            haptics.warning()
            pendingPackedValue = newValue
            isSessionRestartAlertPresented = true
        } else {
            applyToggle(newValue)
        }
    }

    private func applyToggle(_ newValue: Bool) {
        if newValue {
            haptics.success()
        } else {
            haptics.selectionChanged()
        }
        withAnimation {
            runCoil.packed = newValue
        }
    }

    private func deleteRunCoil() {
        haptics.destructiveActionTap()
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
        isDeleteConfirmationPresented = false
    }

    private func handleSessionRestartContinue() {
        haptics.warning()
        guard isSessionRunningForRun else {
            applyToggle(pendingPackedValue)
            isSessionRestartAlertPresented = false
            pendingPackedValue = false
            return
        }
        let run = runCoil.run
        applyToggle(pendingPackedValue)
        sessionController.endSession()
        sessionController.beginSession(for: run)
        isSessionRestartAlertPresented = false
        pendingPackedValue = false
    }
}
