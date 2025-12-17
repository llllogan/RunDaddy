import SwiftUI

struct ExpiringItemsView: View {
    @ObservedObject var viewModel: RunDetailViewModel

    @State private var isAddingNeeded = false
    @State private var addedAlertMessage: String?
    @State private var isShowingAddedAlert = false

    var body: some View {
        Group {
            if let response = viewModel.expiringItems {
                if response.sections.isEmpty {
                    ContentUnavailableView(
                        "No Expiring Items",
                        systemImage: "checkmark.circle",
                        description: Text("Nothing is expiring on the day of this run.")
                    )
                } else {
                    List {
                        ForEach(response.sections) { section in
                            Section() {
                                ForEach(section.items) { item in
                                    ExpiringItemRowView(
                                        skuName: item.sku.name,
                                        skuType: item.sku.type,
                                        machineCode: item.machine.code,
                                        coilCode: item.coil.code,
                                        quantity: item.quantity
                                    )
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            if section.dayOffset == 0 {
                                                Button {
                                                    addNeeded(for: item, runDate: section.expiryDate)
                                                } label: {
                                                    Label("Add \(item.quantity) to coil", systemImage: "plus.circle.fill")
                                                }
                                                .tint(.blue)
                                                .disabled(isAddingNeeded)
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Expiring Items",
                    systemImage: "exclamationmark.triangle",
                    description: Text("We couldn't load expiring items for this run.")
                )
            }
        }
        .navigationTitle("Expiring Items")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Added Needed", isPresented: $isShowingAddedAlert) {
            Button("OK") {
                addedAlertMessage = nil
                Task { @MainActor in
                    await viewModel.loadExpiringItems(force: true)
                }
            }
        } message: {
            Text(addedAlertMessage ?? "")
        }
    }

    private func sectionHeaderText(for section: ExpiringItemsRunResponse.Section) -> String {
        "On day of run (\(section.expiryDate))"
    }

    private func addNeeded(for item: ExpiringItemsRunResponse.Section.Item, runDate: String) {
        if isAddingNeeded {
            return
        }

        isAddingNeeded = true
        Task { @MainActor in
            defer { isAddingNeeded = false }
            do {
                let result = try await viewModel.addNeededForExpiringItem(coilItemId: item.coilItemId)
                let added = result.expiringQuantity > 0 ? result.expiringQuantity : item.quantity
                let coil = result.coilCode
                let dateLabel = result.runDate.isEmpty ? runDate : result.runDate
                addedAlertMessage = "\(added) items have been added to coil \(coil) on \(dateLabel)."
                isShowingAddedAlert = true
            } catch {
                addedAlertMessage = "We couldn't add the needed items right now. Please try again."
                isShowingAddedAlert = true
            }
        }
    }
}
