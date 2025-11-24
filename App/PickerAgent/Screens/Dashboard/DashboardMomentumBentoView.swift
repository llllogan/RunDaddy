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
        StaggeredBentoGrid(items: [analyticsItem], columnCount: 1)
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
