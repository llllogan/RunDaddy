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
    NavigationStack {
        RunDetailView(run: PreviewFixtures.sampleRun)
    }
    .modelContainer(PreviewFixtures.container)
}
