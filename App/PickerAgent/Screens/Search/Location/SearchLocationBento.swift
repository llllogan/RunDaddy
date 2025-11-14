import SwiftUI

struct SearchLocationInfoBento: View {
    let location: Location
    let lastPacked: LocationLastPacked?
    let percentageChange: SkuPercentageChange?
    let bestMachine: LocationBestMachine?
    let bestSku: LocationBestSku?
    let selectedPeriod: SkuPeriod?
    let onBestMachineTap: ((LocationBestMachine) -> Void)?
    let onBestSkuTap: ((LocationBestSku) -> Void)?

    private var items: [BentoItem] {
        var cards: [BentoItem] = []

        cards.append(
            BentoItem(
                title: "Address",
                value: addressValue,
                symbolName: "mappin.circle",
                symbolTint: .orange,
                allowsMultilineValue: true
            )
        )

        cards.append(
            BentoItem(
                title: "Last Packed",
                value: lastPackedValue,
                symbolName: "clock.arrow.circlepath",
                symbolTint: .indigo,
                allowsMultilineValue: true
            )
        )

        if let bestMachine = bestMachine {
            cards.append(
                BentoItem(
                    title: "Best Machine",
                    value: bestMachine.displayName,
                    subtitle: bestMachine.totalPacks > 0 ? "\(bestMachine.totalPacks) packs" : nil,
                    symbolName: "building",
                    symbolTint: .purple,
                    allowsMultilineValue: true,
                    onTap: { onBestMachineTap?(bestMachine) },
                    showsChevron: true
                )
            )
        } else {
            cards.append(
                BentoItem(
                    title: "Best Machine",
                    value: "No data",
                    subtitle: "No machine activity",
                    symbolName: "building",
                    symbolTint: .gray
                )
            )
        }

        if let bestSku = bestSku {
            cards.append(
                BentoItem(
                    title: "Best SKU",
                    value: bestSku.displayName,
                    subtitle: bestSku.totalPacks > 0 ? "\(bestSku.totalPacks) packs" : nil,
                    symbolName: "tag",
                    symbolTint: .teal,
                    allowsMultilineValue: true,
                    onTap: { onBestSkuTap?(bestSku) },
                    showsChevron: true
                )
            )
        } else {
            cards.append(
                BentoItem(
                    title: "Best SKU",
                    value: "No data",
                    subtitle: "No SKU activity",
                    symbolName: "tag",
                    symbolTint: .gray
                )
            )
        }
        
        cards.append(
            BentoItem(
                title: "Pack Trend",
                value: formatPercentageChange(percentageChange),
                subtitle: formatTrendSubtitle(percentageChange?.trend, period: selectedPeriod),
                symbolName: trendSymbol(percentageChange?.trend),
                symbolTint: trendColor(percentageChange?.trend),
                isProminent: percentageChange?.trend == "up"
            )
        )

        return cards
    }

    private var addressValue: String {
        let trimmed = location.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "No address available" : trimmed
    }

    private var lastPackedValue: String {
        guard let lastPacked else { return "No pick history" }
        return formatDate(lastPacked.pickedAt)
    }

    private var lastPackedSubtitle: String? {
        lastPacked?.machineDisplayName
    }

    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        guard let date = formatter.date(from: isoString) else {
            return isoString
        }
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formatPercentageChange(_ change: SkuPercentageChange?) -> String {
        guard let change = change else { return "No data" }
        return String(format: "%@%.1f%%", change.value >= 0 ? "+" : "", change.value)
    }

    private func formatTrendSubtitle(_ trend: String?, period: SkuPeriod?) -> String {
        switch trend {
        case "up":
            return "Up from previous \(period?.displayName ?? "period")"
        case "down":
            return "Down from previous \(period?.displayName ?? "period")"
        case "neutral":
            return "Stable vs previous \(period?.displayName ?? "period")"
        default:
            return "No data"
        }
    }

    private func trendSymbol(_ trend: String?) -> String {
        switch trend {
        case "up":
            return "arrow.up.forward"
        case "down":
            return "arrow.down.left"
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
}
