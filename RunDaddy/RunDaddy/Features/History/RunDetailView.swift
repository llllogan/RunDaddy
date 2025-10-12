//
//  RunDetailView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Charts
import SwiftData
import SwiftUI

struct RunDetailView: View {
    @Bindable var run: Run

    private struct CategorySlice: Identifiable {
        let category: String
        let totalCount: Int

        var id: String { category }
    }

    private var totalUniqueItems: Int {
        run.items.count
    }

    private var totalItemCount: Int {
        run.items.reduce(into: 0) { partialResult, item in
            partialResult += item.count
        }
    }

    private var categorySlices: [CategorySlice] {
        let grouped = Dictionary(grouping: run.items) { item -> String in
            let trimmed = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Uncategorized" : trimmed
        }

        return grouped
            .map { key, items in
                CategorySlice(category: key,
                              totalCount: items.reduce(into: 0) { $0 += $1.count })
            }
            .sorted { lhs, rhs in
                if lhs.totalCount == rhs.totalCount {
                    return lhs.category < rhs.category
                }
                return lhs.totalCount > rhs.totalCount
            }
    }

    private var sortedItems: [InventoryItem] {
        run.items.sorted { lhs, rhs in
            if lhs.category == rhs.category {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section("Overview") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Total Items")
                            .font(.headline)
                        Text("\(totalUniqueItems)")
                            .font(.title3)
                            .bold()
                    }

                    Divider()

                    VStack(alignment: .leading) {
                        Text("Total Quantity")
                            .font(.headline)
                        Text("\(totalItemCount)")
                            .font(.title3)
                            .bold()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Category Breakdown") {
                if categorySlices.isEmpty {
                    Text("No category data available yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(categorySlices) { slice in
                        SectorMark(angle: .value("Count", slice.totalCount))
                            .foregroundStyle(by: .value("Category", slice.category))
                    }
                    .chartLegend(.visible)
                    .frame(height: 240)
                }
            }

            Section("Items") {
                if sortedItems.isEmpty {
                    Text("No items have been imported for this run.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                if !item.code.isEmpty {
                                    Text(item.code)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.category.isEmpty ? "Uncategorized" : item.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Count")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(item.count)")
                                    .font(.headline)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(run.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Run.self, InventoryItem.self, configurations: configuration)

    let context = container.mainContext

    let run = Run(name: "Sample Run")
    context.insert(run)

    let sampleItems = [
        InventoryItem(code: "A1", name: "Item A", count: 2, category: "Socks", run: run),
        InventoryItem(code: "B1", name: "Item B", count: 5, category: "Snacks", run: run),
        InventoryItem(code: "C1", name: "Item C", count: 1, category: "", run: run)
    ]

    sampleItems.forEach { context.insert($0) }

    return NavigationStack {
        RunDetailView(run: run)
    }
    .modelContainer(container)
}
