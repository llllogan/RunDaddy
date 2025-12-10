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
    private let showFilters: Bool
    private let focus: PickEntryBreakdown.ChartItemFocus?
    private let onAggregationChange: ((PickEntryBreakdown.Aggregation) -> Void)?
    @State private var selectedAggregation: PickEntryBreakdown.Aggregation
    @State private var selectedSkuFilter: String?
    @State private var selectedMachineFilter: String?
    @State private var selectedLocationFilter: String?

    init(
        viewModel: ChartsViewModel,
        refreshTrigger: Bool = false,
        showFilters: Bool = false,
        focus: PickEntryBreakdown.ChartItemFocus? = nil,
        onAggregationChange: ((PickEntryBreakdown.Aggregation) -> Void)? = nil,
        applyPadding: Bool = true
    ) {
        self.refreshTrigger = refreshTrigger
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.showFilters = showFilters
        self.focus = focus
        self.onAggregationChange = onAggregationChange
        _selectedAggregation = State(initialValue: viewModel.skuBreakdownAggregation)
        _selectedSkuFilter = State(initialValue: viewModel.skuBreakdownFilters.skuIds.first)
        _selectedMachineFilter = State(initialValue: viewModel.skuBreakdownFilters.machineIds.first)
        _selectedLocationFilter = State(initialValue: viewModel.skuBreakdownFilters.locationIds.first)
    }

    private var orderedPoints: [PickEntryBreakdown.Point] {
        viewModel.skuBreakdownPoints.sorted { $0.start < $1.start }
    }

    private var availableFilters: PickEntryBreakdown.AvailableFilters {
        viewModel.skuBreakdownAvailableFilters
    }

    private var chartSkuCount: Int {
        let skuIds = orderedPoints.flatMap { point in
            point.skus.map(\.skuId)
        }
        return Set(skuIds).count
    }

    private var shouldHideLegend: Bool {
        chartSkuCount > 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Items per ")
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

            if showFilters {
                filterControls
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
                    showLegend: !shouldHideLegend,
                    maxHeight: 220
                )
            }
        }
        .padding()
        .task {
            if let focus {
                viewModel.updateSkuBreakdownFocus(focus)
            }
            await viewModel.loadSkuBreakdown(
                aggregation: viewModel.skuBreakdownAggregation,
                showBars: viewModel.skuBreakdownShowBars,
                focus: focus ?? viewModel.skuBreakdownFocus,
                filters: currentFilters
            )
        }
        .onChange(of: viewModel.skuBreakdownAggregation, initial: false) { _, newValue in
            selectedAggregation = newValue
            onAggregationChange?(newValue)
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                await viewModel.refreshSkuBreakdown()
            }
        }
        .onChange(of: availableFilters) { _, _ in
            syncSelectionWithAvailableFilters()
        }
        .onChange(of: viewModel.skuBreakdownFilters) { _, _ in
            selectedSkuFilter = viewModel.skuBreakdownFilters.skuIds.first
            selectedMachineFilter = viewModel.skuBreakdownFilters.machineIds.first
            selectedLocationFilter = viewModel.skuBreakdownFilters.locationIds.first
        }
    }

    private var currentFilters: PickEntryBreakdown.Filters {
        PickEntryBreakdown.Filters(
            skuIds: availableFilters.sku.isEmpty ? [] : (selectedSkuFilter.map { [$0] } ?? []),
            machineIds: availableFilters.machine.isEmpty ? [] : (selectedMachineFilter.map { [$0] } ?? []),
            locationIds: availableFilters.location.isEmpty ? [] : (selectedLocationFilter.map { [$0] } ?? [])
        )
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if !availableFilters.location.isEmpty {
                    Menu {
                        Button("All Locations") {
                            applyFilters(locationId: nil, machineId: selectedMachineFilter, skuId: selectedSkuFilter)
                        }
                        if !availableFilters.location.isEmpty {
                            Divider()
                        }
                        ForEach(availableFilters.location) { option in
                            Button {
                                applyFilters(locationId: option.id, machineId: selectedMachineFilter, skuId: selectedSkuFilter)
                            } label: {
                                HStack {
                                    Text(option.displayName)
                                    if selectedLocationFilter == option.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        filterChip(label: selectedLocationFilter.flatMap { id in
                            availableFilters.location.first(where: { $0.id == id })?.displayName
                        } ?? "All Locations")
                    }
                }

                if !availableFilters.machine.isEmpty {
                    Menu {
                        Button("All Machines") {
                            applyFilters(locationId: selectedLocationFilter, machineId: nil, skuId: selectedSkuFilter)
                        }
                        if !availableFilters.machine.isEmpty {
                            Divider()
                        }
                        ForEach(availableFilters.machine) { option in
                            Button {
                                applyFilters(locationId: selectedLocationFilter, machineId: option.id, skuId: selectedSkuFilter)
                            } label: {
                                HStack {
                                    Text(option.displayName)
                                    if selectedMachineFilter == option.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        filterChip(label: selectedMachineFilter.flatMap { id in
                            availableFilters.machine.first(where: { $0.id == id })?.displayName
                        } ?? "All Machines")
                    }
                }

                if !availableFilters.sku.isEmpty {
                    Menu {
                        Button("All SKUs") {
                            applyFilters(locationId: selectedLocationFilter, machineId: selectedMachineFilter, skuId: nil)
                        }
                        if !availableFilters.sku.isEmpty {
                            Divider()
                        }
                        ForEach(availableFilters.sku) { option in
                            Button {
                                applyFilters(locationId: selectedLocationFilter, machineId: selectedMachineFilter, skuId: option.id)
                            } label: {
                                HStack {
                                    Text(option.displayName)
                                    if selectedSkuFilter == option.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        filterChip(label: selectedSkuFilter.flatMap { id in
                            availableFilters.sku.first(where: { $0.id == id })?.displayName
                        } ?? "All SKUs")
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func applyFilters(locationId: String?, machineId: String?, skuId: String?) {
        selectedLocationFilter = locationId
        selectedMachineFilter = machineId
        selectedSkuFilter = skuId
        viewModel.updateSkuBreakdownFilters(currentFilters)
    }

    private func syncSelectionWithAvailableFilters() {
        if let locationId = selectedLocationFilter,
           !availableFilters.location.contains(where: { $0.id == locationId }) {
            selectedLocationFilter = nil
        }
        if let machineId = selectedMachineFilter,
           !availableFilters.machine.contains(where: { $0.id == machineId }) {
            selectedMachineFilter = nil
        }
        if let skuId = selectedSkuFilter,
           !availableFilters.sku.contains(where: { $0.id == skuId }) {
            selectedSkuFilter = nil
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
        let endDate: Date
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
                endDate: point.end,
                skus: point.skus,
                totalItems: point.totalItems
            )
        }
    }

    private var labelsByIndex: [Int: String] {
        Dictionary(uniqueKeysWithValues: chartPoints.map { ($0.index, axisLabel(for: $0)) })
    }

    private var currentBucketIndex: Int? {
        let now = Date()
        let match = chartPoints.first { point in
            switch aggregation {
            case .week:
                return calendar.isDate(now, inSameDayAs: point.startDate)
            case .month:
                return calendar.isDate(now, equalTo: point.startDate, toGranularity: .weekOfYear)
            case .quarter:
                return calendar.isDate(now, equalTo: point.startDate, toGranularity: .month)
            }
        }
        return match?.index ?? chartPoints.last?.index
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

    private var highestBarValue: Double {
        chartPoints.map { Double($0.totalItems) }.max() ?? 0
    }

    private var maxYValue: Double {
        let maxOverlay = weekAverageOverlays.map(\.average).max() ?? 0
        let ceiling = max(highestBarValue, maxOverlay)
        return max(ceiling * 1.15, 1)
    }

    private var yAxisValues: [Double] {
        let maxOverlay = weekAverageOverlays.map(\.average).max() ?? 0
        let baseMax = max(highestBarValue, maxOverlay, 1)
        let step = max(1, niceStep(for: baseMax))
        var values = stride(from: 0.0, through: maxYValue, by: step).map { $0 }

        if highestBarValue > 0 {
            values.append(highestBarValue)
        }

        values.sort()
        var deduped: [Double] = []
        for value in values {
            let isHighestBarTick = abs(value - highestBarValue) < 0.0001
            let tooCloseToHighestBar = !isHighestBarTick && highestBarValue > 0 && abs(value - highestBarValue) < step * 0.35
            if tooCloseToHighestBar {
                continue
            }
            if let last = deduped.last, abs(last - value) < max(step * 0.1, 0.0001) {
                continue
            }
            deduped.append(value)
        }

        return deduped
    }

    private func niceStep(for maxValue: Double, targetTickCount: Int = 5) -> Double {
        guard maxValue > 0 else { return 1 }
        let rawStep = maxValue / Double(max(targetTickCount - 1, 1))
        let exponent = pow(10.0, floor(log10(rawStep)))
        let fraction = rawStep / exponent

        let niceFraction: Double
        if fraction < 1.5 {
            niceFraction = 1
        } else if fraction < 3 {
            niceFraction = 2
        } else if fraction < 7 {
            niceFraction = 5
        } else {
            niceFraction = 10
        }

        return niceFraction * exponent
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
            .annotation(position: .top, alignment: .trailing) {
                Text(String(format: "avg %.0f", overlay.average))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                    )
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
            AxisMarks(position: .leading, values: yAxisValues)
        }
        .chartXAxis {
            AxisMarks(values: axisValues) { value in
                if let raw = value.as(Double.self) {
                    let index = Int(raw.rounded())
                    if let label = labelsByIndex[index] {
                        let isCurrentBucket = currentBucketIndex == index
                        AxisValueLabel(anchor: .center) {
                            Text(label)
                                .foregroundStyle(isCurrentBucket ? .primary : .secondary)
                                .fontWeight(isCurrentBucket ? .semibold : .regular)
                        }
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

    init?(aggregation: PickEntryBreakdown.Aggregation) {
        switch aggregation {
        case .week: self = .week
        case .month: self = .month
        case .quarter: self = .quarter
        }
    }
}
