import SwiftUI
import Charts

enum LocationChartBreakdown: String, CaseIterable, Identifiable {
    case machines
    case skus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .machines:
            return "Machines"
        case .skus:
            return "SKUs"
        }
    }

    var seriesLabel: String {
        switch self {
        case .machines:
            return "Machine"
        case .skus:
            return "SKU"
        }
    }
}

struct LocationStatsChartView: View {
    let stats: LocationStatsResponse
    @Binding var selectedPeriod: SkuPeriod
    @Binding var selectedBreakdown: LocationChartBreakdown

    private var aggregation: PickEntryBreakdown.Aggregation { selectedPeriod.pickEntryAggregation }
    private var calendar: Calendar { chartCalendar(for: stats.timeZone) }

    private var hasChartData: Bool {
        breakdownPoints.contains { !$0.skus.isEmpty }
    }

    private var chartSeriesCount: Int {
        let identifiers: [String] = breakdownPoints.flatMap { point in
            point.skus.map(\.skuId)
        }
        return Set(identifiers).count
    }

    private var shouldHideLegend: Bool {
        chartSeriesCount > 6
    }

    private var breakdownPoints: [PickEntryBreakdown.Point] {
        let mapped: [PickEntryBreakdown.Point] = stats.points.compactMap { point in
            guard let start = parseAnalyticsDay(point.date, timeZoneIdentifier: stats.timeZone) else { return nil }
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let segments = chartSegments(for: point).map { segment in
                PickEntryBreakdown.Segment(
                    skuId: segment.id,
                    skuCode: segment.label,
                    skuName: segment.label,
                    totalItems: segment.value
                )
            }

            return PickEntryBreakdown.Point(
                label: point.date,
                start: start,
                end: end,
                totalItems: point.totalItems,
                skus: segments
            )
        }

        guard aggregation == .week else {
            return mapped.sorted { $0.start < $1.start }
        }

        return ensureRollingEightDayWindow(points: mapped, calendar: calendar)
    }

    private var weekAverages: [PickEntryBreakdown.WeekAverage] {
        guard aggregation == .week else { return [] }
        return buildWeekAverages(from: breakdownPoints, calendar: calendar)
    }

    private var lookbackDays: Int {
        if aggregation == .week {
            return max(stats.lookbackDays, 8)
        }
        return max(stats.lookbackDays, aggregation.baseDays)
    }

    private var lookbackText: String {
        let value = max(lookbackDays, breakdownPoints.count)
        return value == 1 ? "1 day" : "\(value) days"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Picks per ")
                    Menu {
                        ForEach(SkuPeriod.allCases) { period in
                            Button(action: { selectedPeriod = period }) {
                                HStack {
                                    Text(period.displayName)
                                    if selectedPeriod == period {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        filterChip(label: selectedPeriod.displayName)
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(LocationChartBreakdown.allCases) { breakdown in
                            Button(action: { selectedBreakdown = breakdown }) {
                                HStack {
                                    Text(breakdown.displayName)
                                    if breakdown == selectedBreakdown {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        filterChip(label: selectedBreakdown.displayName)
                    }
                    .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
            }

            if hasChartData {
                PickEntryBarChart(
                    points: breakdownPoints,
                    aggregation: aggregation,
                    weekAverages: weekAverages,
                    timeZoneIdentifier: stats.timeZone,
                    showLegend: !shouldHideLegend,
                    maxHeight: 220
                )
            } else {
                Text("No data is available for the selected period.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
    }

    private func chartSegments(for point: LocationStatsPoint) -> [LocationChartSegment] {
        switch selectedBreakdown {
        case .machines:
            return point.machines.map { machine in
                LocationChartSegment(id: machine.machineId, label: machine.displayName, value: machine.count)
            }
        case .skus:
            return point.skus.map { sku in
                LocationChartSegment(id: sku.skuId, label: sku.displayName, value: sku.count)
            }
        }
    }

    private struct LocationChartSegment: Identifiable {
        let id: String
        let label: String
        let value: Int
    }
}
