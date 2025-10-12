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

    private static let categoryPalette: [Color] = [
        .accentColor,
        .mint,
        .indigo,
        .orange,
        .teal,
        .pink,
        .purple,
        .brown,
        .cyan,
        .gray
    ]

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

    private var categoryColorLookup: [String: Color] {
        var mapping: [String: Color] = [:]
        for (index, slice) in categorySlices.enumerated() {
            let color = Self.categoryPalette[index % Self.categoryPalette.count]
            mapping[slice.category] = color
        }
        return mapping
    }

    private func color(for category: String) -> Color {
        categoryColorLookup[category] ?? .accentColor
    }

    private var sortedItems: [InventoryItem] {
        run.items.sorted { lhs, rhs in
            if lhs.category == rhs.category {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
        }
    }

    private var pendingItems: [InventoryItem] {
        sortedItems.filter { !$0.checked }
    }

    private var completedItems: [InventoryItem] {
        sortedItems.filter(\.checked)
    }

    private var completedItemCount: Int {
        completedItems.count
    }

    private var completedFraction: Double {
        guard totalUniqueItems > 0 else { return 0 }
        return Double(completedItemCount) / Double(totalUniqueItems)
    }

    private var completionPercentageText: String {
        completedFraction.formatted(.percent.precision(.fractionLength(0)))
    }

    private func toggleCompletion(for item: InventoryItem, isComplete: Bool) {
        withAnimation {
            item.checked = isComplete
            item.dateChecked = isComplete ? Date() : nil
        }
    }

    var body: some View {
        List {
            Section("Overview") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Items")
                            .font(.headline)
                        Text("\(totalUniqueItems)")
                            .font(.title3)
                            .bold()
                    }

                    Divider()

                    VStack(alignment: .leading) {
                        Text("Quantity")
                            .font(.headline)
                        Text("\(totalItemCount)")
                            .font(.title3)
                            .bold()
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Completed")
                            .font(.headline)
                        HStack {
                            Text("\(completedItemCount)")
                                .font(.title3)
                                .bold()
                            Text(completionPercentageText)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Category Breakdown") {
                if categorySlices.isEmpty {
                    Text("No category data available yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Chart(categorySlices) { slice in
                            SectorMark(angle: .value("Count", slice.totalCount))
                                .foregroundStyle(color(for: slice.category))
                        }
                        .frame(height: 240)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], alignment: .leading, spacing: 12) {
                            ForEach(categorySlices) { slice in
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(color(for: slice.category))
                                        .frame(width: 14, height: 14)

                                    Text("\(slice.category) (\(slice.totalCount))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }

            Section("Items") {
                if pendingItems.isEmpty {
                    Text(sortedItems.isEmpty ? "No items have been imported for this run." : "All items are completed.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pendingItems) { item in
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
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleCompletion(for: item, isComplete: true)
                            } label: {
                                Label("Complete", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                    }
                }
            }

            if !completedItems.isEmpty {
                Section("Completed") {
                    ForEach(completedItems) { item in
                        HStack {
                            Label {
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
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
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
                        .swipeActions {
                            Button(role: .destructive) {
                                toggleCompletion(for: item, isComplete: false)
                            } label: {
                                Label("Mark Incomplete", systemImage: "arrow.uturn.left.circle")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(run.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RunDetailView(run: PreviewFixtures.sampleRun)
    }
    .modelContainer(PreviewFixtures.container)
}
