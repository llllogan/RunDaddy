import SwiftUI
import Charts

struct MachineStatsChartView: View {
    let breakdown: PickEntryBreakdown?
    let isLoading: Bool
    let errorMessage: String?
    @Binding var selectedPeriod: SkuPeriod

    private var aggregation: PickEntryBreakdown.Aggregation { selectedPeriod.pickEntryAggregation }
    private var calendar: Calendar { chartCalendar(for: timeZone) }
    private var timeZone: String { breakdown?.timeZone ?? TimeZone.current.identifier }

    private var breakdownPoints: [PickEntryBreakdown.Point] {
        let points = breakdown?.points ?? []
        guard aggregation == .week else { return points.sorted { $0.start < $1.start } }
        return ensureRollingEightDayWindow(points: points, calendar: calendar)
    }

    private var averages: [PickEntryBreakdown.WeekAverage] {
        breakdown?.weekAverages ?? []
    }

    private var hasChartData: Bool {
        breakdownPoints.contains { !$0.skus.isEmpty && $0.totalItems > 0 }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Items per ")
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

            if isLoading && breakdownPoints.isEmpty {
                ProgressView("Loading")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMessage, breakdownPoints.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if hasChartData {
                PickEntryBarChart(
                    points: breakdownPoints,
                    aggregation: aggregation,
                    weekAverages: averages,
                    timeZoneIdentifier: timeZone,
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
