//
//  DashboardMomentumBentoView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/25/2025.
//

import SwiftUI
import Charts

struct DashboardMomentumBentoView: View {
    let snapshot: DashboardMomentumSnapshot
    let onSkuTap: ((DashboardMomentumSnapshot.SkuLeader) -> Void)?
    let onMachineTap: ((DashboardMomentumSnapshot.MachineLeader) -> Void)?
    let onLocationTap: ((DashboardMomentumSnapshot.LocationLeader) -> Void)?
    let onAnalyticsTap: (() -> Void)?

    @State private var skuSelection: DashboardMomentumSnapshot.Direction
    @State private var machineSelection: DashboardMomentumSnapshot.Direction
    @State private var locationSelection: DashboardMomentumSnapshot.Direction

    init(snapshot: DashboardMomentumSnapshot,
         onSkuTap: ((DashboardMomentumSnapshot.SkuLeader) -> Void)? = nil,
         onMachineTap: ((DashboardMomentumSnapshot.MachineLeader) -> Void)? = nil,
         onLocationTap: ((DashboardMomentumSnapshot.LocationLeader) -> Void)? = nil,
         onAnalyticsTap: (() -> Void)? = nil) {
        self.snapshot = snapshot
        self.onSkuTap = onSkuTap
        self.onMachineTap = onMachineTap
        self.onLocationTap = onLocationTap
        self.onAnalyticsTap = onAnalyticsTap
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
            locationItem,
            analyticsItem
        ]
    }

    private var skuItem: BentoItem {
        let momentum = snapshot.skuMomentum
        let tapHandler = navigationHandler(for: activeSkuLeader, handler: onSkuTap)
        let showsChevron = tapHandler != nil
        return BentoItem(
            title: "SKU",
            value: "",
            symbolName: "tag",
            symbolTint: momentum.hasData ? .teal : .gray,
            onTap: tapHandler,
            customContent: AnyView(
                MomentumStatContent<DashboardMomentumSnapshot.SkuLeader>(
                    momentum: momentum,
                    selection: $skuSelection,
                    showsChevron: showsChevron,
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
        let tapHandler = navigationHandler(for: activeMachineLeader, handler: onMachineTap)
        let showsChevron = tapHandler != nil
        return BentoItem(
            title: "Machine",
            value: "",
            symbolName: "building",
            symbolTint: momentum.hasData ? .purple : .gray,
            onTap: tapHandler,
            customContent: AnyView(
                MomentumStatContent<DashboardMomentumSnapshot.MachineLeader>(
                    momentum: momentum,
                    selection: $machineSelection,
                    showsChevron: showsChevron,
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
        let tapHandler = navigationHandler(for: activeLocationLeader, handler: onLocationTap)
        let showsChevron = tapHandler != nil
        return BentoItem(
            title: "Location",
            value: "",
            symbolName: "mappin.circle",
            symbolTint: momentum.hasData ? .orange : .gray,
            onTap: tapHandler,
            customContent: AnyView(
                MomentumStatContent<DashboardMomentumSnapshot.LocationLeader>(
                    momentum: momentum,
                    selection: $locationSelection,
                    showsChevron: showsChevron,
                    placeholderText: "No data yet",
                    primaryText: { $0.displayName },
                    percentageText: { formattedPercentageChange(current: $0.currentTotal, previous: $0.previousTotal) },
                    deltaProvider: { $0.delta }
                )
            )
        )
    }

    private var analyticsItem: BentoItem {
        let hasAction = onAnalyticsTap != nil
        let chartContent: AnyView?
        if let comparison = snapshot.analytics.skuComparison {
            chartContent = AnyView(
                AnalyticsComparisonChart(comparison: comparison)
            )
        } else {
            chartContent = nil
        }

        return BentoItem(
            title: "Analytics",
            value: chartContent == nil ? "See more data" : "",
            subtitle: chartContent == nil ? nil : "See more data",
            symbolName: "chart.bar.xaxis",
            symbolTint: .indigo,
            allowsMultilineValue: true,
            onTap: onAnalyticsTap,
            showsChevron: hasAction,
            customContent: chartContent
        )
    }

    private var activeSkuLeader: DashboardMomentumSnapshot.SkuLeader? {
        activeLeader(from: snapshot.skuMomentum, selection: skuSelection)
    }

    private var activeMachineLeader: DashboardMomentumSnapshot.MachineLeader? {
        activeLeader(from: snapshot.machineMomentum, selection: machineSelection)
    }

    private var activeLocationLeader: DashboardMomentumSnapshot.LocationLeader? {
        activeLeader(from: snapshot.locationMomentum, selection: locationSelection)
    }

    private func activeLeader<Leader>(
        from momentum: DashboardMomentumSnapshot.MomentumLeaders<Leader>,
        selection: DashboardMomentumSnapshot.Direction
    ) -> Leader? {
        momentum.leader(for: selection) ?? momentum.up ?? momentum.down
    }

    private func navigationHandler<Leader>(
        for leader: Leader?,
        handler: ((Leader) -> Void)?
    ) -> (() -> Void)? {
        guard let leader, let handler else {
            return nil
        }
        return {
            handler(leader)
        }
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
    let showsChevron: Bool
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline) {
                    Text(percentageText(leader))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(deltaProvider(leader) >= 0 ? .green : .red)
                    Spacer(minLength: 0)
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
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

private struct AnalyticsComparisonChart: View {
    let comparison: DashboardMomentumSnapshot.AnalyticsSummary.SkuComparison

    private enum WeekBucket: String, CaseIterable, Identifiable {
        case previous
        case current

        var id: String { rawValue }

        var label: String {
            switch self {
            case .previous:
                return "Last Week"
            case .current:
                return "This Week"
            }
        }
    }

    private var hasChartSegments: Bool {
        comparison.segments.contains { $0.previousTotal > 0 || $0.currentTotal > 0 }
    }

    private var maxChartValue: Double {
        let total = max(comparison.totals.maxTotal, 1)
        return Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                if hasChartSegments {
                    ForEach(WeekBucket.allCases) { bucket in
                        ForEach(comparison.segments) { segment in
                            let value = value(for: segment, bucket: bucket)
                            if value > 0 {
                                BarMark(
                                    x: .value("Week", bucket.label),
                                    y: .value("Pick Entries", value)
                                )
                                .foregroundStyle(by: .value("SKU", segment.id))
                                .cornerRadius(6, style: .continuous)
                            }
                        }
                    }
                } else {
                    ForEach(WeekBucket.allCases) { bucket in
                        BarMark(
                            x: .value("Week", bucket.label),
                            y: .value("Pick Entries", 0)
                        )
                        .foregroundStyle(.gray.opacity(0.3))
                        .cornerRadius(6, style: .continuous)
                    }
                }
            }
            .chartLegend(.hidden)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: WeekBucket.allCases.map { $0.label }) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }
            }
            .chartYScale(domain: 0...maxChartValue)
            .frame(height: 100)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pick entry comparison")
        .accessibilityValue("Last week \(comparison.totals.previousWeek) items, this week \(comparison.totals.currentWeek) items")
    }

    private func summaryColumn(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private func value(
        for segment: DashboardMomentumSnapshot.AnalyticsSummary.SkuComparison.Segment,
        bucket: WeekBucket
    ) -> Int {
        switch bucket {
        case .previous:
            return max(segment.previousTotal, 0)
        case .current:
            return max(segment.currentTotal, 0)
        }
    }
}
