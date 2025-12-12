import SwiftUI

struct MachineInfoBento: View {
    let machine: Machine
    let stats: MachineStatsResponse?
    let onLocationTap: ((Location) -> Void)?

    private var cards: [BentoItem] {
        [
            lastStockedCard,
            detailsCard,
            locationCard,
            firstSeenCard
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
            id: "machine-info-details",
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

                    InfoChip(text: chipText, icon: "tray.2.fill")
                    
                    InfoChip(text: machine.code, icon: "barcode")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            )
        )
    }

    private var lastStockedCard: BentoItem {
        let stockedDate = parseDate(stats?.lastStocked?.stockedAt ?? "")
        let isFuture = (stockedDate ?? Date.distantPast) > Date()
        let title = isFuture ? "Next Stocked" : "Last Stocked"

        return BentoItem(
            id: "machine-info-last-stocked",
            title: title,
            value: formatStockedDate(stats?.lastStocked?.stockedAt),
            symbolName: "clock.arrow.circlepath",
            symbolTint: .indigo,
            allowsMultilineValue: true
        )
    }

    private var locationCard: BentoItem {
        let locationName = machine.location?.name ?? "Unassigned"
        let address = machine.location?.address ?? "No address on file"
        let hasLocationLink = (machine.location?.id.isEmpty == false)

        return BentoItem(
            id: "machine-info-location",
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

    private var firstSeenCard: BentoItem {
        guard let firstSeen = stats?.firstSeen,
              let firstSeenDate = parseDate(firstSeen) else {
            return BentoItem(
                id: "machine-info-first-seen",
                title: "First Seen",
                value: "No data",
                symbolName: "calendar.badge.clock",
                symbolTint: .secondary
            )
        }

        return BentoItem(
            id: "machine-info-first-seen",
            title: "First Seen",
            value: formatRelativeDay(from: firstSeenDate),
            subtitle: MachineInfoBento.weekdayFormatter.string(from: firstSeenDate),
            symbolName: "calendar.badge.clock",
            symbolTint: .blue,
            allowsMultilineValue: true
        )
    }

    private func navigateToLocationDetail() {
        guard let location = machine.location else { return }
        onLocationTap?(location)
    }

    var body: some View {
        StaggeredBentoGrid(items: cards, columnCount: 2)
    }

    private func formatStockedDate(_ isoDate: String?) -> String {
        guard let isoDate else {
            return "No data yet"
        }
        if let date = parseDate(isoDate) {
            return formatRelativeDay(from: date)
        }
        return isoDate
    }

    private func parseDate(_ string: String) -> Date? {
        if let date = MachineInfoBento.isoFormatter.date(from: string) {
            return date
        }
        if let date = MachineInfoBento.basicIsoFormatter.date(from: string) {
            return date
        }
        return nil
    }

    private func formatRelativeDay(from date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        return MachineInfoBento.dayMonthFormatter.string(from: date)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basicIsoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

struct MachinePerformanceBento: View {
    let stats: MachineStatsResponse?
    let selectedPeriod: SkuPeriod
    let onBestSkuTap: ((MachineBestSku) -> Void)?
    let highMark: PickEntryBreakdown.Extremum?
    let lowMark: PickEntryBreakdown.Extremum?
    let aggregation: PickEntryBreakdown.Aggregation
    let timeZoneIdentifier: String
    let percentageChange: PickEntryBreakdown.PercentageChange?

    private var cards: [BentoItem] {
        [
            packTrendCard,
            bestSkuCard,
            highMarkCard,
            lowMarkCard
        ]
    }

    private var packTrendCard: BentoItem {
        BentoItem(
            id: "machine-perf-pack-trend",
            title: "Pack Trend",
            value: formatPercentageChange(percentageChange),
            subtitle: formatTrendSubtitle(percentageChange?.trend, period: selectedPeriod),
            symbolName: trendSymbol(percentageChange?.trend),
            symbolTint: trendColor(percentageChange?.trend),
            isProminent: true
        )
    }

    private var bestSkuCard: BentoItem {
        guard let stats, let bestSku = stats.bestSku else {
            return BentoItem(
                id: "machine-perf-best-sku",
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
            id: "machine-perf-best-sku",
            title: "Best SKU",
            value: bestSku.skuName.isEmpty ? bestSku.skuCode : bestSku.skuName,
            subtitle: subtitle,
            symbolName: "tag",
            symbolTint: .teal,
            onTap: { onBestSkuTap?(bestSku) },
            showsChevron: true
        )
    }

    private var highMarkCard: BentoItem {
        extremumCard(
            title: "High",
            extremum: highMark,
            symbolName: "arrow.up.to.line",
            tint: .green,
            isProminent: false
        )
    }

    private var lowMarkCard: BentoItem {
        extremumCard(
            title: "Low",
            extremum: lowMark,
            symbolName: "arrow.down.to.line",
            tint: .orange,
            isProminent: false
        )
    }

    var body: some View {
        StaggeredBentoGrid(items: cards, columnCount: 2)
    }

    private func formatPercentageChange(_ change: PickEntryBreakdown.PercentageChange?) -> String {
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

    private func extremumCard(
        title: String,
        extremum: PickEntryBreakdown.Extremum?,
        symbolName: String,
        tint: Color,
        isProminent: Bool
    ) -> BentoItem {
        guard let extremum else {
            return BentoItem(
                id: "machine-perf-\(title.lowercased())",
                title: title,
                value: "No data",
                symbolName: symbolName,
                symbolTint: .secondary
            )
        }

        return BentoItem(
            id: "machine-perf-\(title.lowercased())",
            title: title,
            value: BreakdownExtremumFormatter.valueText(for: extremum),
            subtitle: BreakdownExtremumFormatter.subtitle(
                for: extremum,
                aggregation: aggregation,
                timeZoneIdentifier: timeZoneIdentifier
            ),
            symbolName: symbolName,
            symbolTint: tint,
            isProminent: isProminent
        )
    }
}
