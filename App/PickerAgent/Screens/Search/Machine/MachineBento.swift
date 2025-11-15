import SwiftUI

struct MachineInfoBento: View {
    let machine: Machine
    let stats: MachineStatsResponse?
    let selectedPeriod: SkuPeriod
    let onBestSkuTap: ((MachineBestSku) -> Void)?
    let onLocationTap: ((Location) -> Void)?

    private var cards: [BentoItem] {
        [
            detailsCard,
            lastStockedCard,
            codeCard,
            locationCard,
            packTrendCard,
            bestSkuCard
        ]
    }

    private var detailsCard: BentoItem {
        let typeName = machine.machineType?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = typeName.isEmpty ? "Unknown type" : typeName
        let typeDescription = machine.machineType?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let chipText: String
        if let typeDescription, !typeDescription.isEmpty {
            chipText = typeDescription
        } else if machine.machineType != nil {
            chipText = "No description yet"
        } else {
            chipText = "No type details"
        }

        return BentoItem(
            title: "Details",
            value: displayName,
            symbolName: "building",
            symbolTint: .purple,
            allowsMultilineValue: true,
            customContent: AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    InfoChip(title: "Type", date: nil, text: chipText, colour: nil, foregroundColour: nil, icon: nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            )
        )
    }

    private var lastStockedCard: BentoItem {
        BentoItem(
            title: "Last Stocked",
            value: formatStockedDate(stats?.lastStocked?.stockedAt),
            symbolName: "clock.arrow.circlepath",
            symbolTint: .indigo,
            allowsMultilineValue: true
        )
    }

    private var codeCard: BentoItem {
        BentoItem(
            title: "Code",
            value: machine.code,
            symbolName: "barcode",
            symbolTint: .blue
        )
    }

    private var locationCard: BentoItem {
        let locationName = machine.location?.name ?? "Unassigned"
        let address = machine.location?.address ?? "No address on file"
        let hasLocationLink = (machine.location?.id.isEmpty == false)

        return BentoItem(
            title: "Location",
            value: locationName,
            subtitle: address,
            symbolName: "mappin.circle",
            symbolTint: .orange,
            allowsMultilineValue: true,
            onTap: hasLocationLink ? { navigateToLocationDetail() } : nil,
            showsChevron: hasLocationLink
        )
    }

    private func navigateToLocationDetail() {
        guard let location = machine.location else { return }
        onLocationTap?(location)
    }

    private var packTrendCard: BentoItem {
        BentoItem(
            title: "Pack Trend",
            value: formatPercentageChange(stats?.percentageChange),
            subtitle: formatTrendSubtitle(stats?.percentageChange?.trend, period: selectedPeriod),
            symbolName: trendSymbol(stats?.percentageChange?.trend),
            symbolTint: trendColor(stats?.percentageChange?.trend),
            isProminent: stats?.percentageChange?.trend == "up"
        )
    }

    private var bestSkuCard: BentoItem {
        guard let stats, let bestSku = stats.bestSku else {
            return BentoItem(
                title: "Best SKU",
                value: "No data",
                subtitle: "No SKU data yet",
                symbolName: "tag",
                symbolTint: .teal
            )
        }

        let trimmedType = bestSku.skuType.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = trimmedType.lowercased() == "general" || trimmedType.isEmpty ? bestSku.skuCode : trimmedType

        return BentoItem(
            title: "Best SKU",
            value: bestSku.skuName.isEmpty ? bestSku.skuCode : bestSku.skuName,
            subtitle: subtitle,
            symbolName: "tag",
            symbolTint: .teal,
            onTap: { onBestSkuTap?(bestSku) },
            showsChevron: true
        )
    }

    var body: some View {
        StaggeredBentoGrid(items: cards, columnCount: 2)
    }

    private func formatStockedDate(_ isoDate: String?) -> String {
        guard let isoDate else {
            return "No data yet"
        }
        if let date = MachineInfoBento.isoFormatter.date(from: isoDate) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return isoDate
    }

    private func formatPercentageChange(_ change: SkuPercentageChange?) -> String {
        guard let change = change else { return "No data" }
        return String(format: "%@%.1f%%", change.value >= 0 ? "+" : "", change.value)
    }

    private func formatTrendSubtitle(_ trend: String?, period: SkuPeriod) -> String {
        switch trend {
        case "up":
            return "Up from previous \(period.displayName)"
        case "down":
            return "Down from previous \(period.displayName)"
        case "neutral":
            return "Stable vs previous \(period.displayName)"
        default:
            return "No data"
        }
    }

    private func trendSymbol(_ trend: String?) -> String {
        switch trend {
        case "up":
            return "arrow.up.forward"
        case "down":
            return "arrow.down.right"
        default:
            return "minus"
        }
    }

    private func trendColor(_ trend: String?) -> Color {
        switch trend {
        case "up":
            return .green
        case "down":
            return .red
        default:
            return .gray
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
