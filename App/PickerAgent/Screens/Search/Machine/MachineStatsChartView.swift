import SwiftUI
import Charts

struct MachineStatsChartView: View {
    let stats: MachineStatsResponse
    @Binding var selectedPeriod: SkuPeriod

    private var aggregation: PickEntryBreakdown.Aggregation { selectedPeriod.pickEntryAggregation }
    private var calendar: Calendar { chartCalendar(for: stats.timeZone) }

    private var hasChartData: Bool {
        breakdownPoints.contains { !$0.skus.isEmpty }
    }

    private var chartSkuCount: Int {
        let skuIds = breakdownPoints.flatMap { point in
            point.skus.map(\.skuId)
        }
        return Set(skuIds).count
    }

    private var shouldHideLegend: Bool {
        chartSkuCount > 6
    }

    private var breakdownPoints: [PickEntryBreakdown.Point] {
        let mapped: [PickEntryBreakdown.Point] = stats.points.compactMap { point in
            guard let start = parseAnalyticsDay(point.date, timeZoneIdentifier: stats.timeZone) else { return nil }
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let segments = point.skus.map { sku in
                PickEntryBreakdown.Segment(
                    skuId: sku.skuId,
                    skuCode: sku.skuCode,
                    skuName: sku.skuName,
                    totalItems: sku.count
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
}
