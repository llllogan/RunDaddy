//
//  SkuBreakdownChartView.swift
//  PickAgent
//
//  Created by ChatGPT on 6/6/2025.
//

import SwiftUI
import Charts

struct SkuBreakdownChartView: View {
    let refreshTrigger: Bool
    @ObservedObject private var viewModel: ChartsViewModel
    @State private var selectedAggregation: PickEntryBreakdown.Aggregation

    init(viewModel: ChartsViewModel, refreshTrigger: Bool = false) {
        self.refreshTrigger = refreshTrigger
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _selectedAggregation = State(initialValue: viewModel.skuBreakdownAggregation)
    }

    private var orderedPoints: [PickEntryBreakdown.Point] {
        viewModel.skuBreakdownPoints.sorted { $0.start < $1.start }
    }

    private var lookbackDays: Int {
        let candidate = viewModel.skuBreakdownPeriods * selectedAggregation.baseDays
        if candidate > 0 {
            return candidate
        }
        return max(orderedPoints.count, selectedAggregation.baseDays)
    }

    private var lookbackText: String {
        let value = lookbackDays
        return value == 1 ? "1 day" : "\(value) days"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Picks per ")
                    Menu {
                        ForEach(PickEntryBreakdown.Aggregation.allCases) { aggregation in
                            Button {
                                selectedAggregation = aggregation
                                viewModel.updateSkuBreakdownAggregation(aggregation)
                            } label: {
                                HStack {
                                    Text(aggregation.displayName)
                                    if aggregation == selectedAggregation {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        filterChip(label: selectedAggregation.displayName)
                    }
                    .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .foregroundStyle(.primary)

                Text("Showing last \(lookbackText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isLoadingSkuBreakdown && orderedPoints.isEmpty {
                ProgressView("Loading")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = viewModel.skuBreakdownError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if orderedPoints.isEmpty {
                Text("SKU activity will appear once picks start landing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PickEntryBarChart(
                    points: orderedPoints,
                    aggregation: selectedAggregation,
                    showLegend: true,
                    maxHeight: 220
                )
            }
        }
        .padding()
        .task {
            await viewModel.loadSkuBreakdown(
                aggregation: viewModel.skuBreakdownAggregation,
                periods: viewModel.skuBreakdownPeriods
            )
        }
        .onChange(of: viewModel.skuBreakdownAggregation, initial: false) { _, newValue in
            selectedAggregation = newValue
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                await viewModel.refreshSkuBreakdown()
            }
        }
    }
}

struct PickEntryBarChart: View {
    let points: [PickEntryBreakdown.Point]
    let aggregation: PickEntryBreakdown.Aggregation
    var showLegend: Bool = true
    var maxHeight: CGFloat = 200

    private struct ChartPoint: Identifiable {
        let id: String
        let anchorDate: Date
        let skus: [PickEntryBreakdown.Segment]
        let totalItems: Int
    }

    private var calendar: Calendar {
        Calendar.current
    }

    private var orderedPoints: [PickEntryBreakdown.Point] {
        points.sorted { $0.start < $1.start }
    }

    private var chartPoints: [ChartPoint] {
        switch aggregation {
        case .week:
            return Array(orderedPoints.suffix(7)).map { point in
                ChartPoint(
                    id: "day-\(point.id.timeIntervalSince1970)",
                    anchorDate: point.start,
                    skus: point.skus,
                    totalItems: point.totalItems
                )
            }
        case .month:
            return aggregatePoints(by: .weekOfYear)
        case .quarter:
            return aggregatePoints(by: .month)
        }
    }

    private var maxYValue: Double {
        let maxValue = chartPoints.map { Double($0.totalItems) }.max() ?? 1
        return max(maxValue * 1.15, 1)
    }

    private var xAxisValues: [Date] {
        chartPoints.map { $0.anchorDate }
    }

    private func aggregatePoints(
        by component: Calendar.Component
    ) -> [ChartPoint] {
        var buckets: [Date: [PickEntryBreakdown.Point]] = [:]

        for point in orderedPoints {
            let bucketStart = bucketStart(for: point.start, component: component)
            buckets[bucketStart, default: []].append(point)
        }

        let sortedBuckets = buckets.keys.sorted()

        return sortedBuckets.compactMap { bucketStart in
            guard let bucketPoints = buckets[bucketStart] else { return nil }
            let segments = aggregateSegments(from: bucketPoints)
            let totalItems = segments.reduce(0) { $0 + $1.totalItems }

            return ChartPoint(
                id: "\(component)-\(bucketStart.timeIntervalSince1970)",
                anchorDate: bucketStart,
                skus: segments,
                totalItems: totalItems
            )
        }
    }

    private func aggregateSegments(from points: [PickEntryBreakdown.Point]) -> [PickEntryBreakdown.Segment] {
        var order: [String] = []
        var totals: [String: (code: String, name: String, total: Int)] = [:]

        for point in points {
            for segment in point.skus {
                if totals[segment.skuId] == nil {
                    totals[segment.skuId] = (segment.skuCode, segment.skuName, 0)
                    order.append(segment.skuId)
                }
                totals[segment.skuId]?.total += segment.totalItems
            }
        }

        return order.compactMap { id in
            guard let info = totals[id] else { return nil }
            return PickEntryBreakdown.Segment(
                skuId: id,
                skuCode: info.code,
                skuName: info.name,
                totalItems: info.total
            )
        }
    }

    private func bucketStart(for date: Date, component: Calendar.Component) -> Date {
        switch component {
        case .weekOfYear:
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: comps) ?? date
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: comps) ?? date
        default:
            return date
        }
    }

    private func weekLabel(for date: Date) -> String {
        let weekNumber = calendar.component(.weekOfYear, from: date)
        return "W\(weekNumber)"
    }

    private func monthLabel(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated))
    }

    private func axisLabel(for date: Date) -> String {
        switch aggregation {
        case .week:
            return date.formatted(.dateTime.day())
        case .month:
            return weekLabel(for: date)
        case .quarter:
            return monthLabel(for: date)
        }
    }

    private var xAxisUnit: Calendar.Component {
        switch aggregation {
        case .week: return .day
        case .month: return .weekOfYear
        case .quarter: return .month
        }
    }

    var body: some View {
        Chart {
            ForEach(chartPoints) { point in
                ForEach(point.skus) { segment in
                    BarMark(
                        x: .value("Period", point.anchorDate, unit: xAxisUnit),
                        y: .value("Pick Entries", segment.totalItems)
                    )
                    .foregroundStyle(by: .value("SKU", segment.displayLabel))
                    .cornerRadius(5, style: .continuous)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(axisLabel(for: date))
                    }
                }
            }
        }
        .chartLegend(showLegend ? .visible : .hidden)
        .chartYScale(domain: 0...maxYValue)
        .frame(height: maxHeight)
    }
}
