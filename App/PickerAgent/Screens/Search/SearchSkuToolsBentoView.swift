import SwiftUI

struct SearchSkuToolsBentoView: View {
    let coldChestSkuCount: Int?
    let missingWeightSkuCount: Int?
    let isLoading: Bool
    let onBulkSetSkuWeight: () -> Void
    let coldChestDestination: AnyView

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onBulkSetSkuWeight()
            } label: {
                BentoCard(item: bulkSetSkuWeightItem)
            }
            .buttonStyle(.plain)

            NavigationLink(destination: coldChestDestination) {
                BentoCard(item: coldChestItem)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var bulkSetSkuWeightItem: BentoItem {
        BentoItem(
            id: "search-bento-bulk-set-sku-weight",
            title: "Bulk set SKU weight",
            value: resolvedCountText(missingWeightSkuCount),
            subtitle: "Go",
            symbolName: "scalemass",
            symbolTint: .orange,
            titleIsProminent: false,
            isProminent: missingWeightSkuCount ?? 0 > 0,
            allowsMultilineValue: true,
            showsChevron: true
        )
    }

    private var coldChestItem: BentoItem {
        BentoItem(
            id: "search-bento-cold-chest",
            title: "Cold Chest",
            value: resolvedCountText(coldChestSkuCount),
            subtitle: "View",
            symbolName: "snowflake",
            symbolTint: Theme.coldChestTint,
            titleIsProminent: false,
            isProminent: coldChestSkuCount ?? 0 > 0,
            showsChevron: true
        )
    }

    private func resolvedCountText(_ count: Int?) -> String {
        if let count {
            return "\(count)"
        }
        return isLoading ? "…" : "—"
    }
}

