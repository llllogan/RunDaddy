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
    let weekAverages: [PickEntryBreakdown.WeekAverage]
    let timeZoneIdentifier: String
    var showLegend: Bool = true
    var maxHeight: CGFloat = 200

    private struct ChartPoint: Identifiable {
        let id: String
        let anchorDate: Date
        let skus: [PickEntryBreakdown.Segment]
        let totalItems: Int
    }

    private struct WeekOverlay: Identifiable {
        let id: String
        let start: Date
        let end: Date
        let average: Double
    }

    private var analyticsTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = analyticsTimeZone
        return calendar
    }

    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    private var orderedPoints: [PickEntryBreakdown.Point] {
        points.sorted { $0.start < $1.start }
    }

    private var chartPoints: [ChartPoint] {
        switch aggregation {
        case .week:
            return Array(orderedPoints.suffix(8)).map { point in
                ChartPoint(
                    id: "day-\(point.id.timeIntervalSince1970)",
                    anchorDate: point.start,
                    skus: point.skus,
                    totalItems: point.totalItems
                )
            }
        case .month:
            return aggregatePoints(from: orderedPoints, by: .weekOfYear)
        case .quarter:
            return aggregatePoints(from: orderedPoints, by: .month)
        }
    }

    private var weekAverageOverlays: [WeekOverlay] {
        guard aggregation == .week else { return [] }
        let visibleDates = Set(chartPoints.map { $0.anchorDate })

        return weekAverages.compactMap { week in
            let includedDates = week.dates
                .filter { visibleDates.contains($0) }
                .sorted()

            guard let firstDate = includedDates.first, let lastDate = includedDates.last else {
                return nil
            }

            let endBoundary = lastDate

            return WeekOverlay(
                id: week.id,
                start: firstDate,
                end: endBoundary,
                average: week.average
            )
        }
    }

    private var maxYValue: Double {
        let maxValue = chartPoints.map { Double($0.totalItems) }.max() ?? 1
        let maxOverlay = weekAverageOverlays.map(\.average).max() ?? 0
        let ceiling = max(maxValue, maxOverlay)
        return max(ceiling * 1.15, 1)
    }

    private var xAxisValues: [Date] {
        chartPoints.map { $0.anchorDate }
    }

    private func aggregatePoints(
        from points: [PickEntryBreakdown.Point],
        by component: Calendar.Component
    ) -> [ChartPoint] {
        var buckets: [Date: [PickEntryBreakdown.Point]] = [:]

        for point in points {
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

    private func axisLabel(for date: Date) -> String {
        switch aggregation {
        case .week:
            let weekdayIndex = calendar.component(.weekday, from: date)
            let index = max(min(weekdayIndex - 1, weekdaySymbols.count - 1), 0)
            let symbol = weekdaySymbols.indices.contains(index) ? weekdaySymbols[index] : ""
            return symbol.first.map(String.init) ?? ""
        case .month:
            return weekLabel(for: date)
        case .quarter:
            let comps = calendar.dateComponents([.month], from: date)
            if let month = comps.month {
                let index = max(min(month - 1, calendar.shortMonthSymbols.count - 1), 0)
                if calendar.shortMonthSymbols.indices.contains(index) {
                    return calendar.shortMonthSymbols[index]
                }
            }
            return ""
        }
    }

    private var xAxisUnit: Calendar.Component {
        switch aggregation {
        case .week: return .day
        case .month: return .weekOfYear
        case .quarter: return .month
        }
    }

    @ChartContentBuilder
    private func barMarks(
        bars: [ChartPoint],
        axisUnit: Calendar.Component
    ) -> some ChartContent {
        ForEach(bars) { point in
            ForEach(point.skus) { segment in
                BarMark(
                    x: .value("Period", point.anchorDate, unit: axisUnit),
                    y: .value("Pick Entries", segment.totalItems)
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
                xStart: .value("Week Start", overlay.start, unit: .day),
                xEnd: .value("Week End", overlay.end, unit: .day),
                y: .value("Weekly Average", overlay.average)
            )
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .foregroundStyle(Color(.secondaryLabel))

            PointMark(
                x: .value("Label Anchor", overlay.start, unit: .day),
                y: .value("Weekly Average", overlay.average)
            )
            .opacity(0)
            .annotation(position: .top, alignment: .leading) {
                Text(String(format: "avg %.0f", overlay.average))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color(.secondaryLabel))
                    .padding(.leading, -16)
            }
        }
    }

    var body: some View {
        let bars = chartPoints
        let overlays = weekAverageOverlays
        let axisValues = xAxisValues
        let axisUnit = xAxisUnit
        let yMax = maxYValue

        return Chart {
            barMarks(bars: bars, axisUnit: axisUnit)
            overlayMarks(overlays: overlays)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: axisValues) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        let label = axisLabel(for: date)
                        let isToday = calendar.isDateInToday(date)
                        Text(label)
                            .foregroundStyle(isToday ? Color.primary : Color.secondary)
                    }
                }
            }
        }
        .chartLegend(showLegend ? .visible : .hidden)
        .chartYScale(domain: 0...yMax)
        .frame(height: maxHeight)
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
