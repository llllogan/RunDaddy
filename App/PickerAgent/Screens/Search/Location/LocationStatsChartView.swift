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

    private var hasChartData: Bool {
        stats.points.contains { point in
            switch selectedBreakdown {
            case .machines:
                return !point.machines.isEmpty
            case .skus:
                return !point.skus.isEmpty
            }
        }
    }

    private var chartSeriesCount: Int {
        let identifiers: [String] = stats.points.flatMap { point in
            switch selectedBreakdown {
            case .machines:
                return point.machines.map(\.machineId)
            case .skus:
                return point.skus.map(\.skuId)
            }
        }
        return Set(identifiers).count
    }

    private var shouldHideLegend: Bool {
        chartSeriesCount > 6
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
            ForEach(stats.points) { point in
                let dayLabel = pointLabel(for: point)
                let series = chartSegments(for: point)
                if series.isEmpty {
                    BarMark(
                        x: .value("Day", dayLabel),
                        y: .value("Items", 0)
                    )
                    .foregroundStyle(.gray)
                    .opacity(0.6)
                } else {
                    ForEach(series) { segment in
                        BarMark(
                            x: .value("Day", dayLabel),
                            y: .value("Items", segment.value)
                        )
                        .foregroundStyle(by: .value(selectedBreakdown.seriesLabel, segment.label))
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

    private func pointLabel(for point: LocationStatsPoint) -> String {
        if let date = Self.inputDateFormatter.date(from: point.date) {
            return Self.displayFormatter.string(from: date)
        }
        return point.date
    }

    private struct LocationChartSegment: Identifiable {
        let id: String
        let label: String
        let value: Int
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
