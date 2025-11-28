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
                    weekAverages: viewModel.skuBreakdownWeekAverages,
                    timeZoneIdentifier: viewModel.skuBreakdownTimeZone,
                    showLegend: true,
                    maxHeight: 220
                )
            }
        }
        .padding()
        .task {
            await viewModel.loadSkuBreakdown(
                aggregation: viewModel.skuBreakdownAggregation,
                showBars: viewModel.skuBreakdownShowBars
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
    let weekAverages: [PickEntryBreakdown.WeekAverage]
    let timeZoneIdentifier: String
    var showLegend: Bool = true
    var maxHeight: CGFloat = 200
    @State private var scrollPosition: Double = 0
    private var barWidth: Double {
        switch aggregation {
        case .week: return 30
        case .month: return 36
        case .quarter: return 55
        }
    }
    private struct ChartPoint: Identifiable {
        let id: String
        let index: Int
        let label: String
        let key: String
        let startDate: Date
        let skus: [PickEntryBreakdown.Segment]
        let totalItems: Int
    }

    private struct WeekOverlay: Identifiable {
        let id: String
        let startIndex: Int
        let endIndex: Int
        let average: Double
    }

    private var orderedPoints: [PickEntryBreakdown.Point] {
        points.sorted { $0.start < $1.start }
    }

    private var calendar: Calendar {
        chartCalendar(for: timeZoneIdentifier)
    }

    private var chartPoints: [ChartPoint] {
        orderedPoints.enumerated().map { index, point in
            ChartPoint(
                id: "period-\(index)",
                index: index,
                label: point.label,
                key: "p\(index)",
                startDate: point.start,
                skus: point.skus,
                totalItems: point.totalItems
            )
        }
    }

    private var labelsByIndex: [Int: String] {
        Dictionary(uniqueKeysWithValues: chartPoints.map { ($0.index, axisLabel(for: $0)) })
    }

    private var weekAverageOverlays: [WeekOverlay] {
        func indexRange(for start: Date, end: Date) -> (Int, Int)? {
            let matches = chartPoints.filter { point in
                point.startDate >= start && point.startDate <= end
            }
            guard let first = matches.min(by: { $0.index < $1.index }),
                  let last = matches.max(by: { $0.index < $1.index }) else {
                return nil
            }
            return (first.index, last.index)
        }

        return weekAverages.compactMap { week in
            if let range = indexRange(for: week.weekStart, end: week.weekEnd) {
                return WeekOverlay(id: week.id, startIndex: range.0, endIndex: range.1, average: week.average)
            }
            if let firstIndex = chartPoints.first?.index, let lastIndex = chartPoints.last?.index {
                return WeekOverlay(id: week.id, startIndex: firstIndex, endIndex: lastIndex, average: week.average)
            }
            return nil
        }
    }

    private var maxYValue: Double {
        let maxValue = chartPoints.map { Double($0.totalItems) }.max() ?? 1
        let maxOverlay = weekAverageOverlays.map(\.average).max() ?? 0
        let ceiling = max(maxValue, maxOverlay)
        return max(ceiling * 1.15, 1)
    }

    private func axisLabel(for point: ChartPoint) -> String {
        switch aggregation {
        case .week:
            let weekday = calendar.component(.weekday, from: point.startDate)
            let index = max(min(weekday - 1, calendar.shortWeekdaySymbols.count - 1), 0)
            let symbol = calendar.shortWeekdaySymbols.indices.contains(index) ? calendar.shortWeekdaySymbols[index] : ""
            return symbol.first.map(String.init) ?? point.label
        case .month:
            let weekNumber = calendar.component(.weekOfYear, from: point.startDate)
            return "W\(weekNumber)"
        case .quarter:
            let month = calendar.component(.month, from: point.startDate)
            let index = max(min(month - 1, calendar.shortMonthSymbols.count - 1), 0)
            return calendar.shortMonthSymbols.indices.contains(index) ? calendar.shortMonthSymbols[index] : point.label
        }
    }

    @ChartContentBuilder
    private func barMarks(
        bars: [ChartPoint]
    ) -> some ChartContent {
        ForEach(bars) { point in
            ForEach(point.skus) { segment in
                BarMark(
                    x: .value("Period", point.index),
                    y: .value("Pick Entries", segment.totalItems),
                    width: .fixed(barWidth)
                )
                .foregroundStyle(by: .value("SKU", segment.displayLabel))
                .cornerRadius(5, style: .continuous)
            }
        }
    }

    @ChartContentBuilder
    private func overlayMarks(
        overlays: [WeekOverlay]
    ) -> some ChartContent {
        ForEach(overlays) { overlay in
            RuleMark(
                xStart: .value("Period Start", Double(overlay.startIndex) - 0.5),
                xEnd: .value("Period End", Double(overlay.endIndex) + 0.5),
                y: .value("Weekly Average", overlay.average)
            )
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .foregroundStyle(Color(.secondaryLabel))
            .annotation(position: .top, alignment: .leading) {
                Text(String(format: "avg %.0f", overlay.average))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color(.secondaryLabel))
                    .offset(x: 2, y: 0)
            }
        }
    }

    var body: some View {
        let bars = chartPoints
        let overlays = weekAverageOverlays
        let axisValues = chartPoints.map { Double($0.index) }
        let yMax = maxYValue
        let visibleCount = aggregation.defaultBars
        let domainEnd = max((bars.count - 1), (visibleCount - 1), 0)
        let xDomain: ClosedRange<Double> = -0.5...(Double(domainEnd) + 0.5)

        return Chart {
            barMarks(bars: bars)
            overlayMarks(overlays: overlays)
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: Double(visibleCount))
        .chartScrollPosition(x: $scrollPosition)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: axisValues) { value in
                if let raw = value.as(Double.self) {
                    let index = Int(raw.rounded())
                    if let label = labelsByIndex[index] {
                        AxisValueLabel(label, anchor: .center)
                            .offset(x: -barWidth / 2.0)
                    }
                }
            }
        }
        .chartXScale(domain: xDomain, range: .plotDimension(padding: 0))
        .chartLegend(showLegend ? .visible : .hidden)
        .chartYScale(domain: 0...yMax)
        .frame(height: maxHeight)
        .onAppear {
            scrollPosition = Double(domainEnd)
        }
        .onChange(of: domainEnd) { _, newValue in
            scrollPosition = Double(newValue)
        }
    }
}

func chartCalendar(for timeZoneIdentifier: String) -> Calendar {
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    return calendar
}

func parseAnalyticsDay(_ dateString: String, timeZoneIdentifier: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    return formatter.date(from: dateString)
}

func ensureRollingEightDayWindow(
    points: [PickEntryBreakdown.Point],
    calendar: Calendar
) -> [PickEntryBreakdown.Point] {
    let labelFormatter = DateFormatter()
    labelFormatter.dateFormat = "yyyy-MM-dd"
    labelFormatter.timeZone = calendar.timeZone

    let today = calendar.startOfDay(for: Date())
    var byDay: [Date: PickEntryBreakdown.Point] = [:]

    for point in points {
        let dayStart = calendar.startOfDay(for: point.start)
        byDay[dayStart] = point
    }

    let offsets = (-6...1)
    let filledPoints: [PickEntryBreakdown.Point] = offsets.compactMap { offset in
        guard let dayStart = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
        if let existing = byDay[dayStart] {
            // normalize start/end to the anchored day to avoid drift
            let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            return PickEntryBreakdown.Point(
                label: existing.label,
                start: dayStart,
                end: end,
                totalItems: existing.totalItems,
                skus: existing.skus
            )
        }

        let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return PickEntryBreakdown.Point(
            label: labelFormatter.string(from: dayStart),
            start: dayStart,
            end: end,
            totalItems: 0,
            skus: []
        )
    }

    return filledPoints.sorted { $0.start < $1.start }
}

func buildWeekAverages(
    from points: [PickEntryBreakdown.Point],
    calendar: Calendar
) -> [PickEntryBreakdown.WeekAverage] {
    var buckets: [Date: [PickEntryBreakdown.Point]] = [:]

    for point in points {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: point.start)
        let weekStart = calendar.date(from: comps) ?? point.start
        buckets[weekStart, default: []].append(point)
    }

    return buckets.keys.sorted().compactMap { weekStart in
        guard let bucketPoints = buckets[weekStart] else { return nil }
        let dates = bucketPoints.map(\.start).sorted()
        guard let lastDate = dates.last else { return nil }
        let total = bucketPoints.reduce(0) { $0 + $1.totalItems }
        let average = bucketPoints.isEmpty ? 0 : Double(total) / Double(bucketPoints.count)

        return PickEntryBreakdown.WeekAverage(
            weekStart: weekStart,
            weekEnd: lastDate,
            dates: dates,
            average: average
        )
    }
}

extension SkuPeriod {
    var pickEntryAggregation: PickEntryBreakdown.Aggregation {
        switch self {
        case .week: return .week
        case .month: return .month
        case .quarter: return .quarter
        }
    }
}
