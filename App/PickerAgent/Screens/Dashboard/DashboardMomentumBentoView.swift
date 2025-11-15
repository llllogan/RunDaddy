//
//  DashboardMomentumBentoView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/25/2025.
//

import SwiftUI

struct DashboardMomentumBentoView: View {
    let snapshot: DashboardMomentumSnapshot

    @State private var skuSelection: DashboardMomentumSnapshot.Direction
    @State private var machineSelection: DashboardMomentumSnapshot.Direction
    @State private var locationSelection: DashboardMomentumSnapshot.Direction

    init(snapshot: DashboardMomentumSnapshot) {
        self.snapshot = snapshot
        _skuSelection = State(initialValue: snapshot.skuMomentum.defaultSelection)
        _machineSelection = State(initialValue: snapshot.machineMomentum.defaultSelection)
        _locationSelection = State(initialValue: snapshot.locationMomentum.defaultSelection)
    }

    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
            .onChange(of: snapshot, initial: false) { _, newSnapshot in
                skuSelection = newSnapshot.skuMomentum.defaultSelection
                machineSelection = newSnapshot.machineMomentum.defaultSelection
                locationSelection = newSnapshot.locationMomentum.defaultSelection
            }
    }

    private var items: [BentoItem] {
        [
            skuItem,
            machineItem,
            locationItem
        ]
    }

    private var skuItem: BentoItem {
        let momentum = snapshot.skuMomentum
        return BentoItem(
            title: "SKU Momentum",
            value: "",
            symbolName: "tag",
            symbolTint: momentum.hasData ? .teal : .gray,
            customContent: AnyView(
                MomentumStatContent<DashboardMomentumSnapshot.SkuLeader>(
                    momentum: momentum,
                    selection: $skuSelection,
                    placeholderText: "No data yet",
                    primaryText: { $0.displayName },
                    percentageText: { formattedPercentageChange(current: $0.currentTotal, previous: $0.previousTotal) },
                    deltaProvider: { $0.delta }
                )
            )
        )
    }

    private var machineItem: BentoItem {
        let momentum = snapshot.machineMomentum
        return BentoItem(
            title: "Machine Momentum",
            value: "",
            symbolName: "building",
            symbolTint: momentum.hasData ? .purple : .gray,
            customContent: AnyView(
                MomentumStatContent<DashboardMomentumSnapshot.MachineLeader>(
                    momentum: momentum,
                    selection: $machineSelection,
                    placeholderText: "No data yet",
                    primaryText: { leader in
                        if let location = leader.locationDisplayName {
                            return "\(location) • \(leader.displayName)"
                        }
                        return leader.displayName
                    },
                    percentageText: { formattedPercentageChange(current: $0.currentTotal, previous: $0.previousTotal) },
                    deltaProvider: { $0.delta }
                )
            )
        )
    }

    private var locationItem: BentoItem {
        let momentum = snapshot.locationMomentum
        return BentoItem(
            title: "Location Momentum",
            value: "",
            symbolName: "mappin.circle",
            symbolTint: momentum.hasData ? .orange : .gray,
            customContent: AnyView(
                MomentumStatContent<DashboardMomentumSnapshot.LocationLeader>(
                    momentum: momentum,
                    selection: $locationSelection,
                    placeholderText: "No data yet",
                    primaryText: { $0.displayName },
                    percentageText: { formattedPercentageChange(current: $0.currentTotal, previous: $0.previousTotal) },
                    deltaProvider: { $0.delta }
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

private struct MomentumStatContent<Leader: Equatable>: View {
    let momentum: DashboardMomentumSnapshot.MomentumLeaders<Leader>
    @Binding var selection: DashboardMomentumSnapshot.Direction
    let placeholderText: String
    let primaryText: (Leader) -> String
    let percentageText: (Leader) -> String
    let deltaProvider: (Leader) -> Int

    private var activeLeader: Leader? {
        momentum.leader(for: selection) ?? momentum.up ?? momentum.down
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let leader = activeLeader {
                Text(primaryText(leader))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(percentageText(leader))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(deltaProvider(leader) >= 0 ? .green : .red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(placeholderText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if momentum.allowsDirectionToggle {
                Picker("Direction", selection: $selection) {
                    ForEach(DashboardMomentumSnapshot.Direction.allCases, id: \.self) { direction in
                        Text(direction.label)
                            .tag(direction)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
