//
//  RunLocationDetailView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI

struct RunLocationDetailView: View {
    @EnvironmentObject private var sessionController: PackingSessionController
    @Environment(\.haptics) private var haptics
    @State private var expandedMachineIDs: Set<String> = []
    let run: Run
    let section: RunLocationSection

    private var locationRunCoils: [RunCoil] {
        section.machines.flatMap(\.coils)
    }

    private var packedCount: Int {
        locationRunCoils.filter(\.packed).count
    }

    private var notPackedCount: Int {
        max(locationRunCoils.count - packedCount, 0)
    }

    private var hasPackedItems: Bool {
        locationRunCoils.contains(where: \.packed)
    }

    var body: some View {
        List {
            Section {
                LocationOverviewBento(section: section,
                                      packedCount: packedCount,
                                      notPackedCount: notPackedCount)
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                Text("Location Overview")
            }

            Section {
                if section.machines.isEmpty {
                    Text("No machines for this location.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(section.machines) { machineSection in
                        LocationMachineListItem(machineSection: machineSection,
                                                isExpanded: binding(forMachineID: machineSection.id))
                    }
                }
            } header: {
                LocationMachinesSectionHeader(machineCount: section.machineCount,
                                              coilCount: section.coilCount)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expandedMachineIDs)
        .navigationTitle(section.location.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        sessionController.beginSession(for: run)
                    } label: {
                        Label("Start Packing", systemImage: "tray")
                    }
                    .disabled(locationRunCoils.isEmpty)
                    .accessibilityLabel("Start packing session")
                    Button {
                        haptics.secondaryButtonTap()
                        markAllItemsAsUnpacked()
                    } label: {
                        Label("Reset Packing Status", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!hasPackedItems)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Run actions")
            }
        }
        .onChange(of: section.id) {
            expandedMachineIDs.removeAll()
        }
    }

    private func binding(forMachineID id: String) -> Binding<Bool> {
        Binding(
            get: { expandedMachineIDs.contains(id) },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if newValue {
                        expandedMachineIDs.insert(id)
                    } else {
                        expandedMachineIDs.remove(id)
                    }
                }
            }
        )
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

struct LocationMachineListItem: View {
    let machineSection: RunMachineSection
    @Binding var isExpanded: Bool

    private var machine: Machine { machineSection.machine }
    private var coilCount: Int { machineSection.coilCount }
    private var packedCount: Int { machineSection.coils.filter(\.packed).count }
    private var remainingCount: Int { max(coilCount - packedCount, 0) }
    private var coilLabel: String { coilCount == 1 ? "coil" : "coils" }

    private var summary: String {
        guard coilCount > 0 else { return "No coils assigned" }
        if remainingCount == 0 {
            return "All \(coilCount) \(coilLabel) packed"
        }
        let remainingLabel = remainingCount == 1 ? "coil remaining" : "coils remaining"
        return "\(coilCount) \(coilLabel) • \(remainingCount) \(remainingLabel)"
    }

    private var statusText: String {
        guard coilCount > 0 else { return "0" }
        return "\(packedCount)/\(coilCount)"
    }

    private var statusColor: Color {
        guard coilCount > 0 else { return .secondary }
        return remainingCount == 0 ? .green : .primary
    }

    var body: some View {
        Group {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {

                    VStack(alignment: .leading, spacing: 4) {
                        Text(machine.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(statusText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(statusColor)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
            .accessibilityElement(children: .combine)
            .accessibilityHint("Tap to \(isExpanded ? "collapse" : "expand") machine items")

            if isExpanded {
                ForEach(machineSection.coils) { runCoil in
                    CoilRow(runCoil: runCoil)
                        .listRowInsets(.init(top: 4, leading: 64, bottom: 4, trailing: 16))
                }
            }
        }
    }
}
