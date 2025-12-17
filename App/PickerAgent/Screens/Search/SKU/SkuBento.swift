//
//  SkuBento.swift
//  PickerAgent
//
//  Created by Logan Janssen on 13/11/2025.
//

import SwiftUI

struct SkuInfoBento: View {
    let sku: SKU
    let isUpdatingColdChestStatus: Bool
    let onToggleColdChestStatus: () -> Void
    let mostRecentPick: MostRecentPick?
    let labelColour: Binding<Color>
    let isUpdatingLabelColour: Bool
    let canEditLabelColour: Bool
    let isUpdatingExpiryDays: Bool
    let firstSeen: String?
    let onConfigureExpiryDays: () -> Void
    
    private var items: [BentoItem] {
        var cards: [BentoItem] = []
        
        cards.append(
            BentoItem(id: "sku-info-details",
                      title: "Details",
                      value: sku.type,
                      symbolName: "tag",
                      symbolTint: .teal,
                      allowsMultilineValue: true,
                      customContent: AnyView(
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sku.type)
                                .font(.title3.weight(.semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            InfoChip(text: sku.category ?? "None", icon: "tray.fill")
                            
                            InfoChip(text: sku.code, icon: "barcode")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                      ))
        )
        
        cards.append(
            BentoItem(id: "sku-info-fresh",
              title: "Cold Chest",
              value: sku.isFreshOrFrozen ? "Enabled" : "Disabled",
              symbolName: "snowflake",
              symbolTint: sku.isFreshOrFrozen ? Theme.coldChestTint : .secondary,
              showsChevron: false,
              customContent: AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if isUpdatingColdChestStatus {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(sku.isFreshOrFrozen ? "In Cold Chest" : "Not in Cold Chest")
                                .font(.headline)
                                .foregroundColor(sku.isFreshOrFrozen ? Theme.coldChestTint : .secondary)
                        }
                        Spacer()
                        Image(systemName: sku.isFreshOrFrozen ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(sku.isFreshOrFrozen ? Theme.coldChestTint : .secondary)
                    }

                    Text("Tap to toggle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if sku.isFreshOrFrozen {
                        labelColourSelection
                    }
                }
                .background(
                    Button {
                        if isUpdatingColdChestStatus {
                            return
                        }
                        onToggleColdChestStatus()
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdatingColdChestStatus)
                )
            ))
        )
        
        cards.append(weightCard)
        
        cards.append(expiryDaysCard)
        
        if let mostRecentPick = mostRecentPick {
            cards.append(
                BentoItem(id: "sku-info-last-packed",
                          title: lastPackedTitle,
                          value: formatDate(mostRecentPick.pickedAt),
                          symbolName: "clock",
                          symbolTint: .indigo,
                          allowsMultilineValue: true)
            )
        }
        
        cards.append(firstSeenCard)

        return cards
    }
    
    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
    }
    
    private var firstSeenCard: BentoItem {
        guard let firstSeen,
              let firstSeenDate = parseDate(firstSeen) else {
            return BentoItem(
                id: "sku-perf-first-seen",
                title: "First Seen",
                value: "No data",
                symbolName: "calendar.badge.clock",
                symbolTint: .secondary
            )
        }

        return BentoItem(
            id: "sku-perf-first-seen",
            title: "First Seen",
            value: formatRelativeDay(from: firstSeenDate),
            subtitle: SkuInfoBento.weekdayFormatter.string(from: firstSeenDate),
            symbolName: "calendar.badge.clock",
            symbolTint: .blue,
            allowsMultilineValue: true
        )
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
        return SkuInfoBento.dayMonthFormatter.string(from: date)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = Locale.current
        return formatter
    }()

    private var lastPackedTitle: String {
        guard let pick = mostRecentPick,
              let date = parseDate(pick.pickedAt) else {
            return "Last Packed"
        }
        return date > Date() ? "Next Packed" : "Last Packed"
    }
    
    private func formatDate(_ dateString: String) -> String {
        guard let date = parseDate(dateString) else {
            return dateString
        }

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

        return SkuInfoBento.dayMonthFormatter.string(from: date)
    }

    private func parseDate(_ dateString: String) -> Date? {
        if let date = SkuInfoBento.isoFormatter.date(from: dateString) {
            return date
        }
        return SkuInfoBento.basicIsoFormatter.date(from: dateString)
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
        formatter.locale = Locale.current
        return formatter
    }()

    private var weightCard: BentoItem {
        guard let weight = sku.weight else {
            return BentoItem(
                id: "sku-info-weight",
                title: "Weight",
                value: "Not set",
                symbolName: "scalemass",
                symbolTint: .secondary
            )
        }

        return BentoItem(
            id: "sku-info-weight",
            title: "Weight",
            value: formattedWeight(weight),
            symbolName: "scalemass",
            symbolTint: .orange,
            isProminent: true
        )
    }

    private var expiryDaysCard: BentoItem {
        let valueText: String
        if let expiryDays = sku.expiryDays, expiryDays > 0 {
            valueText = "\(expiryDays) days"
        } else {
            valueText = "Not set"
        }

        return BentoItem(
            id: "sku-info-expiry-days",
            title: "Shelf Lifespan",
            value: isUpdatingExpiryDays ? "Saving…" : valueText,
            subtitle: "Configure",
            symbolName: "calendar.badge.clock",
            symbolTint: .green,
            isProminent: false,
            onTap: onConfigureExpiryDays,
            showsChevron: true
        )
    }

    private func formattedWeight(_ value: Double) -> String {
        let formattedValue = SkuInfoBento.weightFormatter.string(from: NSNumber(value: value))
        return "\(formattedValue ?? "\(value)") g"
    }

    private static let weightFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter
    }()

    // Label colour picker has been folded into the Cold Chest card.

    private var labelColourHex: String? {
        ColorCodec.hexString(from: labelColour.wrappedValue)
    }

    private var labelColourSelection: some View {
        HStack(spacing: 4) {
            ColorPicker("", selection: labelColour, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 34, height: 34)

            Text("Select SKU label colour")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(!canEditLabelColour)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray5))
        )
        .accessibilityLabel("Select SKU label colour")
    }
}

struct SkuPerformanceBento: View {
    let percentageChange: PickEntryBreakdown.PercentageChange?
    let bestMachine: SkuBestMachine?
    let selectedPeriod: SkuPeriod?
    let onBestMachineTap: ((SkuBestMachine) -> Void)?
    let highMark: PickEntryBreakdown.Extremum?
    let lowMark: PickEntryBreakdown.Extremum?
    let aggregation: PickEntryBreakdown.Aggregation
    let timeZoneIdentifier: String

    private var items: [BentoItem] {
        [
            packTrendCard,
            bestMachineCard,
            highMarkCard,
            lowMarkCard
        ]
    }

    private var packTrendCard: BentoItem {
        BentoItem(
            id: "sku-perf-pack-trend",
            title: "Pack Trend",
            value: formatPercentageChange(percentageChange),
            subtitle: formatTrendSubtitle(percentageChange?.trend, period: selectedPeriod),
            symbolName: trendSymbol(percentageChange?.trend),
            symbolTint: trendColor(percentageChange?.trend),
            isProminent: true
        )
    }

    private var bestMachineCard: BentoItem {
        guard let bestMachine else {
            return BentoItem(
                id: "sku-perf-best-machine",
                title: "Best Machine",
                value: "No data",
                subtitle: "No machine data yet",
                symbolName: "building",
                symbolTint: .purple
            )
        }

        return BentoItem(
            id: "sku-perf-best-machine",
            title: "Best Machine",
            value: (bestMachine.machineName?.isEmpty == false ? bestMachine.machineName : nil) ?? bestMachine.machineCode,
            subtitle: bestMachine.locationName ?? bestMachine.machineCode,
            symbolName: "building",
            symbolTint: .purple,
            onTap: { onBestMachineTap?(bestMachine) },
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
        StaggeredBentoGrid(items: items, columnCount: 2)
    }

    private func formatPercentageChange(_ change: PickEntryBreakdown.PercentageChange?) -> String {
        guard let change = change else { return "No Data" }
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
                id: "sku-perf-\(title.lowercased())",
                title: title,
                value: "No data",
                symbolName: symbolName,
                symbolTint: .secondary
            )
        }

        return BentoItem(
            id: "sku-perf-\(title.lowercased())",
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

    private func parseDate(_ string: String) -> Date? {
        if let date = SkuPerformanceBento.isoFormatter.date(from: string) {
            return date
        }
        return SkuPerformanceBento.basicIsoFormatter.date(from: string)
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
}
