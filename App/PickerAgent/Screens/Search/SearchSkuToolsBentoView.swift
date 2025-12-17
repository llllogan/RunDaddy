import SwiftUI

struct SearchSkuToolsBentoView: View {
    let coldChestSkuCount: Int?
    let missingWeightSkuCount: Int?
    let isLoading: Bool
    let onBulkSetSkuWeight: () -> Void
    let onColdChestTap: () -> Void

    var body: some View {
        StaggeredBentoGrid(items: [bulkSetSkuWeightItem, coldChestItem], columnCount: 2)
    }

    private var bulkSetSkuWeightItem: BentoItem {
        BentoItem(
            id: "search-bento-bulk-set-sku-weight",
            title: "Bulk Update Weight",
            value: resolvedCountTextWeight(missingWeightSkuCount),
            subtitle: "Go",
            symbolName: "scalemass",
            symbolTint: .orange,
            titleIsProminent: false,
            isProminent: missingWeightSkuCount ?? 0 > 0,
            allowsMultilineValue: true,
            onTap: onBulkSetSkuWeight,
            showsChevron: true
        )
    }

    private var coldChestItem: BentoItem {
        BentoItem(
            id: "search-bento-cold-chest",
            title: "Cold Chest",
            value: resolvedCountTextColdChest(coldChestSkuCount),
            subtitle: "View",
            symbolName: "snowflake",
            symbolTint: Theme.coldChestTint,
            titleIsProminent: false,
            isProminent: coldChestSkuCount ?? 0 > 0,
            onTap: onColdChestTap,
            showsChevron: true
        )
    }

    private func resolvedCountTextColdChest(_ count: Int?) -> String {
        if let count {
            return "\(count) SKUs"
        }
        return isLoading ? "…" : "—"
    }
    
    private func resolvedCountTextWeight(_ count: Int?) -> String {
        if let count {
            return "\(count) without weight"
        }
        return isLoading ? "…" : "—"
    }
}
