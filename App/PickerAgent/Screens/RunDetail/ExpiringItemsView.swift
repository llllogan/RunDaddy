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
                        description: Text("Nothing is expiring today, yesterday, or two days ago for this run.")
                    )
                } else {
                    List {
                        ForEach(response.sections) { section in
                            Section(header: Text(sectionHeaderText(for: section))) {
                                ForEach(section.items) { item in
                                    ExpiringItemRow(item: item)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            if section.dayOffset == 0 {
                                                Button {
                                                    addNeeded(for: item, runDate: section.expiryDate)
                                                } label: {
                                                    Label("Add Needed", systemImage: "arrow.up.to.line")
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
        switch section.dayOffset {
        case 0:
            return "On day of run (\(section.expiryDate))"
        case -1, -2:
            return "\(relativeDayLabel(for: section.expiryDate)) (\(section.expiryDate))"
        default:
            return section.expiryDate
        }
    }

    private func relativeDayLabel(for dateString: String) -> String {
        guard let date = Self.parseLocalDateOnly(dateString) else {
            return dateString
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)

        if calendar.isDate(target, inSameDayAs: today) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(target, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today),
           calendar.isDate(target, inSameDayAs: twoDaysAgo) {
            return "2 days ago"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(target, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }

        return dateString
    }

    private static func parseLocalDateOnly(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
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
                let added = result.addedQuantity
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

private struct ExpiringItemRow: View {
    let item: ExpiringItemsRunResponse.Section.Item

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.sku.name)
                    .font(.headline)
                    .lineLimit(2)

                Text("\(item.machine.code) • Coil \(item.coil.code)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.quantity)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("EXPIRING")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
