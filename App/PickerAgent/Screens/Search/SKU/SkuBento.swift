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
    
    private var items: [BentoItem] {
        var cards: [BentoItem] = []
        
        cards.append(
            BentoItem(title: "Code",
                      value: sku.code,
                      symbolName: "barcode",
                      symbolTint: .blue)
        )
        
        cards.append(
            BentoItem(title: "Name",
                      value: sku.name,
                      symbolName: "tag",
                      symbolTint: .green,
                      allowsMultilineValue: true)
        )
        
        cards.append(
            BentoItem(title: "Type",
                      value: sku.type,
                      symbolName: "cube.box",
                      symbolTint: .orange)
        )
        
        cards.append(
            BentoItem(title: "Category",
                      value: sku.category ?? "None",
                      symbolName: "folder",
                      symbolTint: .purple)
        )
        
        cards.append(
            BentoItem(title: "Cheese & Crackers",
                      value: sku.isCheeseAndCrackers ? "Enabled" : "Disabled",
                      subtitle: "Tap to toggle",
                      symbolName: sku.isCheeseAndCrackers ? "checkmark.circle.fill" : "xmark.circle.fill",
                      symbolTint: sku.isCheeseAndCrackers ? .green : .red,
                      onTap: { onToggleCheeseStatus() },
                      showsChevron: false,
                      customContent: AnyView(
                        HStack {
                            if isUpdatingCheeseStatus {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text(sku.isCheeseAndCrackers ? "Enabled" : "Disabled")
                                    .font(.headline)
                                    .foregroundColor(sku.isCheeseAndCrackers ? .green : .red)
                            }
                            Spacer()
                            Image(systemName: sku.isCheeseAndCrackers ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(sku.isCheeseAndCrackers ? .green : .red)
                        }
                    ))
        )
        
        return cards
    }
    
    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
    }
}

struct SkuStatsBento: View {
    let mostRecentPick: MostRecentPick?
    let weekChange: SkuPercentageChange?
    let monthChange: SkuPercentageChange?
    let quarterChange: SkuPercentageChange?
    
    private var items: [BentoItem] {
        var cards: [BentoItem] = []
        
        if let mostRecentPick = mostRecentPick {
            cards.append(
                BentoItem(title: "Most Recent Pick",
                          value: formatDate(mostRecentPick.pickedAt),
                          subtitle: "\(mostRecentPick.locationName) • \(mostRecentPick.runId)",
                          symbolName: "clock",
                          symbolTint: .indigo,
                          allowsMultilineValue: true)
            )
        }
        
        cards.append(
            BentoItem(title: "Week Change",
                      value: formatPercentageChange(weekChange),
                      symbolName: trendSymbol(weekChange?.trend),
                      symbolTint: trendColor(weekChange?.trend),
                      isProminent: weekChange?.trend == "up")
        )
        
        cards.append(
            BentoItem(title: "Month Change",
                      value: formatPercentageChange(monthChange),
                      symbolName: trendSymbol(monthChange?.trend),
                      symbolTint: trendColor(monthChange?.trend),
                      isProminent: monthChange?.trend == "up")
        )
        
        cards.append(
            BentoItem(title: "Quarter Change",
                      value: formatPercentageChange(quarterChange),
                      symbolName: trendSymbol(quarterChange?.trend),
                      symbolTint: trendColor(quarterChange?.trend),
                      isProminent: quarterChange?.trend == "up")
        )
        
        return cards
    }
    
    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatPercentageChange(_ change: SkuPercentageChange?) -> String {
        guard let change = change else { return "No Data" }
        return String(format: "%@%.1f%%", change.value >= 0 ? "+" : "", change.value)
    }
    
    private func trendSymbol(_ trend: String?) -> String {
        switch trend {
        case "up":
            return "arrow.up"
        case "down":
            return "arrow.down"
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

