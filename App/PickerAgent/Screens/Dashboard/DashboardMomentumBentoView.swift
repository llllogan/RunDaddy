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
        StaggeredBentoGrid(items: [machineTouchesItem, analyticsItem], columnCount: 2)
    }

    private var machineTouchesItem: BentoItem {
        let orderedPoints = snapshot.machineTouches.sorted { $0.weekStart < $1.weekStart }
        let hasData = orderedPoints.contains { $0.totalMachines > 0 }
        let chartContent = MachineTouchesLineChart(points: orderedPoints)

        return BentoItem(
            title: "Machine Reach",
            value: machineTouchHeadline(for: orderedPoints),
            subtitle: orderedPoints.isEmpty ? "No machine activity yet" : "Machines touched per week",
            symbolName: "waveform.path.ecg.rectangle",
            symbolTint: hasData ? .blue : .gray,
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

private struct MachineTouchesLineChart: View {
    let points: [DashboardMomentumSnapshot.MachineTouchPoint]

    private var orderedPoints: [DashboardMomentumSnapshot.MachineTouchPoint] {
        points.sorted { $0.weekStart < $1.weekStart }
    }

    private var maxValue: Double {
        let maxTotal = orderedPoints.map(\.totalMachines).max() ?? 0
        return max(Double(maxTotal), 1)
    }

    private static let axisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if orderedPoints.isEmpty {
                Text("Machine activity will appear once picks start landing each week.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Chart(orderedPoints) { point in
                    AreaMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Machines", point.totalMachines)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                .blue.opacity(0.24),
                                .blue.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Machines", point.totalMachines)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))

                    PointMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Machines", point.totalMachines)
                    )
                    .foregroundStyle(.blue)
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: orderedPoints.map { $0.weekStart }) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(Self.axisFormatter.string(from: date))
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...maxValue)
                .frame(height: 170)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
