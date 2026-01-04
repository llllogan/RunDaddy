import SwiftUI

struct ExpiringItemsView: View {
    @ObservedObject var viewModel: RunDetailViewModel

    @State private var isAddingNeeded = false
    @State private var addedAlertMessage: String?
    @State private var isShowingAddedAlert = false
    @State private var isPerformingAction = false

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
                                    expiringItemRow(item: item, section: section)
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
        .alert("Expiring Items", isPresented: $isShowingAddedAlert) {
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

    private func formattedExpiryDateLabel(_ expiryDate: String) -> String {
        guard let date = Self.expiryFormatter.date(from: expiryDate) else {
            return expiryDate
        }

        let calendar = Calendar.current
        let dayTitle: String
        if calendar.isDateInToday(date) {
            dayTitle = "Today"
        } else if calendar.isDateInTomorrow(date) {
            dayTitle = "Tomorrow"
        } else {
            dayTitle = Self.weekdayFormatter.string(from: date)
        }

        let dayNumber = Self.dayFormatter.string(from: date)
        let rawMonth = Self.monthFormatter.string(from: date)
        let month = rawMonth.first.map { String($0).uppercased() + rawMonth.dropFirst().lowercased() } ?? rawMonth
        return "\(dayTitle)  \(dayNumber) \(month)"
    }

    private func machineDisplayName(for item: ExpiringItemsRunResponse.Section.Item) -> String {
        let description = item.machine.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return description.isEmpty ? item.machine.code : description
    }

    private func itemLabel(for count: Int) -> String {
        count == 1 ? "item" : "items"
    }

    @ViewBuilder
    private func expiringItemRow(
        item: ExpiringItemsRunResponse.Section.Item,
        section: ExpiringItemsRunResponse.Section
    ) -> some View {
        let statusMessage = item.isIgnored ? "Ignored" : nil

        let baseRow = ExpiringItemRowView(
            skuName: item.sku.name,
            skuType: item.sku.type,
            machineCode: machineDisplayName(for: item),
            coilCode: item.coil.code,
            quantity: item.quantity,
            stockingMessage: statusMessage,
            stockingMessageColor: .secondary
        )

        let row = baseRow.swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if item.isIgnored {
                Button {
                    undoIgnore(item: item, expiryDate: section.expiryDate)
                } label: {
                    Label("Undo Ignore", systemImage: "arrow.uturn.left")
                }
                .tint(.blue)
                .disabled(isPerformingAction)
            } else {
                Button {
                    ignore(item: item, expiryDate: section.expiryDate)
                } label: {
                    Label("Ignore", systemImage: "eye.slash")
                }
                .tint(.gray)
                .disabled(isPerformingAction)
            }
        }

        if item.isIgnored || section.dayOffset != 0 {
            row
        } else {
            row.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    addNeeded(for: item, runDate: section.expiryDate)
                } label: {
                    Label("Add \(item.quantity) to coil", systemImage: "plus")
                }
                .tint(.blue)
                .disabled(isAddingNeeded)
            }
        }
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
                let dateLabel = result.runDate.isEmpty ? runDate : result.runDate
                let machineName = machineDisplayName(for: item)
                addedAlertMessage = "Added \(added) \(itemLabel(for: added)) to \(machineName) for \(formattedExpiryDateLabel(dateLabel))."
                isShowingAddedAlert = true
            } catch {
                addedAlertMessage = "We couldn't add the needed items right now. Please try again."
                isShowingAddedAlert = true
            }
        }
    }

    private func ignore(item: ExpiringItemsRunResponse.Section.Item, expiryDate: String) {
        guard !isPerformingAction else {
            return
        }

        isPerformingAction = true
        Task { @MainActor in
            defer { isPerformingAction = false }
            do {
                try await viewModel.ignoreExpiry(item: item, expiryDate: expiryDate)
                await viewModel.loadExpiringItems(force: true)
            } catch {
                addedAlertMessage = "We couldn't ignore that expiry right now. Please try again."
                isShowingAddedAlert = true
            }
        }
    }

    private func undoIgnore(item: ExpiringItemsRunResponse.Section.Item, expiryDate: String) {
        guard !isPerformingAction else {
            return
        }

        isPerformingAction = true
        Task { @MainActor in
            defer { isPerformingAction = false }
            do {
                try await viewModel.undoIgnoreExpiry(item: item, expiryDate: expiryDate)
                await viewModel.loadExpiringItems(force: true)
            } catch {
                addedAlertMessage = "We couldn't undo that ignore right now. Please try again."
                isShowingAddedAlert = true
            }
        }
    }

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "dd"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM"
        return formatter
    }()
}
