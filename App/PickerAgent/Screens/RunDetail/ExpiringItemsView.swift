import SwiftUI

struct ExpiringItemsView: View {
    let runId: String
    let response: ExpiringItemsRunResponse?

    var body: some View {
        Group {
            if let response {
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
    }

    private func sectionHeaderText(for section: ExpiringItemsRunResponse.Section) -> String {
        let relative: String
        switch section.dayOffset {
        case 0:
            relative = "Today"
        case -1:
            relative = "Yesterday"
        case -2:
            relative = "2 days ago"
        default:
            relative = section.expiryDate
        }

        return "\(relative) (\(section.expiryDate))"
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
