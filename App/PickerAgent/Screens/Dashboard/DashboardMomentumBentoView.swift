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
    let onAnalyticsTap: (() -> Void)?

    var body: some View {
        StaggeredBentoGrid(items: [machineItem, analyticsItem], columnCount: 2)
    }

    private var machineItem: BentoItem {
        let hasData = snapshot.machinePickTotals.isEmpty == false
        let chartContent = MachineDonutChart(slices: snapshot.machinePickTotals)

        return BentoItem(
            title: "Machines",
            value: hasData ? machineTotalDisplay : "No data yet",
            subtitle: "Last 2 weeks",
            symbolName: "gearshape.2",
            symbolTint: hasData ? .purple : .gray,
            allowsMultilineValue: true,
            customContent: AnyView(chartContent)
        )
    }

    private var machineTotalDisplay: String {
        let total = snapshot.machinePickTotals.reduce(0) { $0 + $1.totalPicks }
        return total == 1 ? "1 pick entry" : "\(total) pick entries"
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

private struct MachineDonutChart: View {
    let slices: [DashboardMomentumSnapshot.MachineSlice]

    private var totalPicks: Int {
        slices.reduce(0) { $0 + $1.totalPicks }
    }

    private var orderedSlices: [DashboardMomentumSnapshot.MachineSlice] {
        slices.sorted { $0.totalPicks > $1.totalPicks }
    }

    private var topMachines: [DashboardMomentumSnapshot.MachineSlice] {
        Array(orderedSlices.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if slices.isEmpty {
                Text("No picks recorded in the last 2 weeks.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Chart(orderedSlices) { slice in
                    SectorMark(
                        angle: .value("Pick Entries", slice.totalPicks)
                    )
                    .foregroundStyle(by: .value("Machine", slice.displayName))
                    .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .frame(height: 180)

                if topMachines.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(topMachines.enumerated()), id: \.element.id) { index, slice in
                            HStack {
                                Text("\(index + 1). \(slice.displayName)")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                Text(percentageText(for: slice))
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percentageText(for slice: DashboardMomentumSnapshot.MachineSlice) -> String {
        guard totalPicks > 0 else { return "0%" }
        let percentage = Double(slice.totalPicks) / Double(totalPicks) * 100
        return "\(Int((percentage).rounded()))%"
    }
}
