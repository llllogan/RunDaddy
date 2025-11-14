import SwiftUI
import Charts

struct MachineStatsChartView: View {
    let stats: MachineStatsResponse
    @Binding var selectedPeriod: SkuPeriod

    private var hasChartData: Bool {
        stats.points.contains { !$0.skus.isEmpty }
    }

    private var chartSkuCount: Int {
        let skuIds = stats.points.flatMap { point in
            point.skus.map(\.skuId)
        }
        return Set(skuIds).count
    }

    private var shouldHideLegend: Bool {
        chartSkuCount > 6
    }

    private var maxYValue: Double {
        let maxPoint = stats.points.map { Double($0.totalItems) }.max() ?? 1
        return max(maxPoint, 1) * 1.2
    }

    private var orderedDayLabels: [String] {
        stats.points
            .map(pointLabel(for:))
            .reducingUnique()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 2) {
                Text("Totals for the last ")
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

            if hasChartData {
                chartView
            } else {
                Text("No data is available for the selected period.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
    }

    @ViewBuilder
    private var chartView: some View {
        let chart = Chart {
            ForEach(stats.points, id: \.date) { point in
                let dayLabel = pointLabel(for: point)
                if point.skus.isEmpty {
                    BarMark(
                        x: .value("Day", dayLabel),
                        y: .value("Items", 0)
                    )
                    .foregroundStyle(.gray)
                    .opacity(0.6)
                } else {
                    ForEach(point.skus) { sku in
                        let skuLabel = sku.skuName.isEmpty ? sku.skuCode : sku.skuName
                        BarMark(
                            x: .value("Day", dayLabel),
                            y: .value("Items", sku.count)
                        )
                        .foregroundStyle(by: .value("SKU", skuLabel))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: orderedDayLabels) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .chartYScale(domain: 0...maxYValue)
        .frame(height: 240)

        if shouldHideLegend {
            chart
                .chartLegend(.hidden)
        } else {
            chart
                .chartLegend(position: .top, alignment: .leading)
        }
    }

    private func pointLabel(for point: MachineStatsPoint) -> String {
        if let date = chartDate(from: point.date) {
            return MachineStatsChartView.displayFormatter.string(from: date)
        }
        return point.date
    }

    private func chartDate(from string: String) -> Date? {
        MachineStatsChartView.inputDateFormatter.date(from: string)
    }

    private static let inputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

private extension Sequence where Element: Hashable {
    func reducingUnique() -> [Element] {
        var seen = Set<Element>()
        return compactMap { element in
            let inserted = seen.insert(element).inserted
            return inserted ? element : nil
        }
    }
}
