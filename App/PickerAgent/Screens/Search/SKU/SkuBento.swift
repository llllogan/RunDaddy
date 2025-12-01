//
//  SkuBento.swift
//  PickerAgent
//
//  Created by Logan Janssen on 13/11/2025.
//

import SwiftUI

struct SkuInfoBento: View {
    let sku: SKU
    let isUpdatingCheeseStatus: Bool
    let onToggleCheeseStatus: () -> Void
    let mostRecentPick: MostRecentPick?
    
    private var items: [BentoItem] {
        var cards: [BentoItem] = []
        
        cards.append(
            BentoItem(title: "Details",
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
                            
                            InfoChip(title: "Category", text: sku.category ?? "None")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                      ))
        )
        
        if let mostRecentPick = mostRecentPick {
            cards.append(
                BentoItem(title: lastPackedTitle,
                          value: formatDate(mostRecentPick.pickedAt),
                          symbolName: "clock",
                          symbolTint: .indigo,
                          allowsMultilineValue: true)
            )
        }
        
        cards.append(
            BentoItem(title: "Code",
                      value: sku.code,
                      symbolName: "barcode",
                      symbolTint: .blue)
        )
        
        cards.append(
            BentoItem(title: "Cheese Tub",
                      value: sku.isCheeseAndCrackers ? "Enabled" : "Disabled",
                      subtitle: "Tap to toggle",
                      symbolName: sku.isCheeseAndCrackers ? "square.fill" : "square.fill",
                      symbolTint: sku.isCheeseAndCrackers ? .yellow : .secondary,
                      onTap: { onToggleCheeseStatus() },
                      showsChevron: false,
                      customContent: AnyView(
                        HStack {
                            if isUpdatingCheeseStatus {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text(sku.isCheeseAndCrackers ? "Included" : "Not Included")
                                    .font(.headline)
                                    .foregroundColor(sku.isCheeseAndCrackers ? .yellow : .secondary)
                            }
                            Spacer()
                            Image(systemName: sku.isCheeseAndCrackers ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(sku.isCheeseAndCrackers ? .green : .secondary)
                        }
                    ))
        )
        
        return cards
    }
    
    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
    }

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
}

struct SkuPerformanceBento: View {
    let percentageChange: SkuPercentageChange?
    let bestMachine: SkuBestMachine?
    let selectedPeriod: SkuPeriod?
    let onBestMachineTap: ((SkuBestMachine) -> Void)?

    private var items: [BentoItem] {
        [
            packTrendCard,
            bestMachineCard
        ]
    }

    private var packTrendCard: BentoItem {
        BentoItem(
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
                title: "Best Machine",
                value: "No data",
                subtitle: "No machine data yet",
                symbolName: "building",
                symbolTint: .purple
            )
        }

        return BentoItem(
            title: "Best Machine",
            value: (bestMachine.machineName?.isEmpty == false ? bestMachine.machineName : nil) ?? bestMachine.machineCode,
            subtitle: bestMachine.locationName ?? bestMachine.machineCode,
            symbolName: "building",
            symbolTint: .purple,
            onTap: { onBestMachineTap?(bestMachine) },
            showsChevron: true
        )
    }

    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
    }

    private func formatPercentageChange(_ change: SkuPercentageChange?) -> String {
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
}
