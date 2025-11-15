//
//  DashboardMomentumBentoView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/25/2025.
//

import SwiftUI

struct DashboardMomentumBentoView: View {
    let snapshot: DashboardMomentumSnapshot

    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
    }

    private var items: [BentoItem] {
        [
            skuItem,
            machineItem,
            locationItem
        ]
    }

    private var skuItem: BentoItem {
        guard let leader = snapshot.skuLeader else {
            return BentoItem(
                title: "SKU Momentum",
                value: "",
                symbolName: "tag",
                symbolTint: .gray,
                customContent: AnyView(MomentumStatContent(primaryText: "No data yet", percentageText: nil))
            )
        }

        return BentoItem(
            title: "SKU Momentum",
            value: "",
            symbolName: "tag",
            symbolTint: .teal,
            customContent: AnyView(
                MomentumStatContent(
                    primaryText: leader.displayName,
                    percentageText: formattedPercentageChange(current: leader.currentTotal, previous: leader.previousTotal)
                )
            )
        )
    }

    private var machineItem: BentoItem {
        guard let leader = snapshot.machineLeader else {
            return BentoItem(
                title: "Machine Momentum",
                value: "",
                symbolName: "building",
                symbolTint: .gray,
                customContent: AnyView(MomentumStatContent(primaryText: "No data yet", percentageText: nil))
            )
        }

        let name = leader.locationDisplayName.map { "\($0) • \(leader.displayName)" } ?? leader.displayName

        return BentoItem(
            title: "Machine Momentum",
            value: "",
            symbolName: "building",
            symbolTint: .purple,
            customContent: AnyView(
                MomentumStatContent(
                    primaryText: name,
                    percentageText: formattedPercentageChange(current: leader.currentTotal, previous: leader.previousTotal)
                )
            )
        )
    }

    private var locationItem: BentoItem {
        guard let leader = snapshot.locationLeader else {
            return BentoItem(
                title: "Location Momentum",
                value: "",
                symbolName: "mappin.circle",
                symbolTint: .gray,
                customContent: AnyView(MomentumStatContent(primaryText: "No data yet", percentageText: nil))
            )
        }

        return BentoItem(
            title: "Location Momentum",
            value: "",
            symbolName: "mappin.circle",
            symbolTint: .orange,
            customContent: AnyView(
                MomentumStatContent(
                    primaryText: leader.displayName,
                    percentageText: formattedPercentageChange(current: leader.currentTotal, previous: leader.previousTotal)
                )
            )
        )
    }

    private func formattedPercentageChange(current: Int, previous: Int) -> String {
        let sanitizedCurrent = max(current, 0)
        let sanitizedPrevious = max(previous, 0)

        if sanitizedPrevious == 0 {
            if sanitizedCurrent == 0 {
                return "0%"
            }
            return "+100%"
        }

        let delta = Double(sanitizedCurrent - sanitizedPrevious) / Double(sanitizedPrevious) * 100
        let clampedDelta = max(min(delta, 999), -999)
        return String(format: "%@%.0f%%", clampedDelta >= 0 ? "+" : "", clampedDelta)
    }
}

private struct MomentumStatContent: View {
    let primaryText: String
    let percentageText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(primaryText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let percentageText {
                Text(percentageText)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
