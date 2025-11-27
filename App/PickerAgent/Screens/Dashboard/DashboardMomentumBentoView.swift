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
    let pickEntryBreakdown: PickEntryBreakdown?
    let onAnalyticsTap: (() -> Void)?

    var body: some View {
        StaggeredBentoGrid(items: [machineTouchesItem, analyticsItem], columnCount: 2)
    }

    private var machineTouchesItem: BentoItem {
        let orderedPoints = snapshot.machineTouches.sorted { $0.weekStart < $1.weekStart }
        let hasData = orderedPoints.contains { $0.totalMachines > 0 }
        let chartContent = MachineTouchesLineChart(points: orderedPoints)

        return BentoItem(
            title: "Total Machines",
            value: machineTouchHeadline(for: orderedPoints),
            symbolName: "building.2",
            symbolTint: hasData ? .purple : .gray,
            allowsMultilineValue: true,
            customContent: AnyView(chartContent)
        )
    }

    private func machineTouchHeadline(for points: [DashboardMomentumSnapshot.MachineTouchPoint]) -> String {
        guard let latest = points.last else {
            return "No machines yet"
        }

        let machineNoun = latest.totalMachines == 1 ? "machine" : "machines"

        guard let previous = points.dropLast().last else {
            return "\(latest.totalMachines) \(machineNoun)"
        }

        let delta = latest.totalMachines - previous.totalMachines
        let sign = delta > 0 ? "+" : ""
        if delta == 0 {
            return "\(latest.totalMachines) \(machineNoun) (no change)"
        }
        return "\(latest.totalMachines) \(machineNoun) (\(sign)\(delta) vs prior)"
    }

    private var analyticsItem: BentoItem {
        let hasAction = onAnalyticsTap != nil
        let chartContent: AnyView?
        let headline = breakdownLookbackText

        if let breakdown = pickEntryBreakdown, let chart = dashboardPickEntryChart(from: breakdown) {
            chartContent = AnyView(chart)
        } else if let comparison = snapshot.analytics.skuComparison {
            chartContent = AnyView(AnalyticsComparisonChart(comparison: comparison))
        } else {
            chartContent = nil
        }

        return BentoItem(
            title: "Picks",
            value: headline,
            symbolName: "tag",
            symbolTint: .cyan,
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
                                .font(.caption.weight(.light))
                        }
                    }
                }
            }
            .chartYScale(domain: 0...maxChartValue)
            .frame(height: 170)
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

private extension DashboardMomentumBentoView {
    var breakdownLookbackText: String {
        guard let breakdown = pickEntryBreakdown else {
            return ""
        }
        let dayCount = breakdown.points.count
        if dayCount <= 0 {
            return ""
        }
        return dayCount == 1 ? "Last 1 day" : "Last \(dayCount) days"
    }

    private struct WeekKey: Hashable {
        let year: Int
        let week: Int
    }

    private struct WeekBucket: Identifiable {
        let id = UUID()
        let label: String
        let segments: [PickEntryBreakdown.Segment]
    }

    private func dashboardPickEntryChart(from breakdown: PickEntryBreakdown) -> AnyView? {
        let buckets = buildWeekBuckets(from: breakdown)
        guard !buckets.isEmpty else { return nil }

        let chart = VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(buckets) { bucket in
                    ForEach(bucket.segments) { segment in
                        if segment.totalItems > 0 {
                            BarMark(
                                x: .value("Week", bucket.label),
                                y: .value("Pick Entries", segment.totalItems)
                            )
                            .foregroundStyle(by: .value("SKU", segment.displayLabel))
                            .cornerRadius(6, style: .continuous)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: buckets.map { $0.label }) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.caption.weight(.light))
                        }
                    }
                }
            }
            .frame(height: 170)
        }

        return AnyView(chart)
    }

    private func buildWeekBuckets(from breakdown: PickEntryBreakdown) -> [WeekBucket] {
        let calendar = Calendar(identifier: .iso8601)
        var totalsByWeek: [WeekKey: [String: PickEntryBreakdown.Segment]] = [:]
        for point in breakdown.points {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: point.start)
            guard let year = components.yearForWeekOfYear, let week = components.weekOfYear else {
                continue
            }
            let key = WeekKey(year: year, week: week)
            var segments = totalsByWeek[key] ?? [:]
            for segment in point.skus {
                let existing = segments[segment.skuId]
                let mergedTotal = (existing?.totalItems ?? 0) + segment.totalItems
                segments[segment.skuId] = PickEntryBreakdown.Segment(
                    skuId: segment.skuId,
                    skuCode: segment.skuCode,
                    skuName: segment.skuName,
                    totalItems: mergedTotal
                )
            }
            totalsByWeek[key] = segments
        }

        let orderedKeys = totalsByWeek.keys.sorted { lhs, rhs in
            if lhs.year == rhs.year {
                return lhs.week < rhs.week
            }
            return lhs.year < rhs.year
        }
        let latestKeys = Array(orderedKeys.suffix(2))

        return latestKeys.enumerated().map { index, key in
            let label = index == latestKeys.count - 1 ? "This Week" : "Last Week"
            let weekSegments = totalsByWeek[key].map { Array($0.values) } ?? []
            let segments = weekSegments.sorted { $0.totalItems > $1.totalItems }
            return WeekBucket(label: label, segments: segments)
        }
    }
}
