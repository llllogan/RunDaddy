//
//  SkuStatsChartView.swift
//  PickerAgent
//
//  Created by Logan Janssen on 11/13/2025.
//

import SwiftUI
import Charts

struct SkuStatsChartView: View {
    let stats: SkuStatsResponse
    @Binding var selectedPeriod: SkuPeriod
    @Binding var selectedLocationFilter: String?
    @Binding var selectedMachineFilter: String?
    let onFilterChange: (_ locationId: String?, _ machineId: String?) async -> Void

    private var locationOptions: [SkuStatsLocationOption] { stats.locations }
    private var machineOptions: [SkuStatsMachineOption] { stats.machines }

    private var visibleMachines: [SkuStatsMachineOption] {
        guard let locationId = selectedLocationFilter else {
            return machineOptions
        }
        return machineOptions.filter { $0.locationId == locationId }
    }

    private var locationFilterLabel: String {
        guard let selectedLocationFilter,
              let location = locationOptions.first(where: { $0.id == selectedLocationFilter }) else {
            return "All Locations"
        }
        return location.displayName
    }

    private var machineFilterLabel: String {
        guard let selectedMachineFilter,
              let machine = machineOptions.first(where: { $0.id == selectedMachineFilter }) else {
            return "All Machines"
        }
        return machine.displayName
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
            
            filterControls

            if hasChartData {
                chartView
            } else {
                Text("No data is available for the selected period.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .onChange(of: locationOptions) { _, _ in
            guard let selection = selectedLocationFilter else { return }
            if locationOptions.first(where: { $0.id == selection }) == nil {
                selectedLocationFilter = nil
                selectedMachineFilter = nil
                applyFilters(locationId: nil, machineId: nil)
            }
        }
        .onChange(of: machineOptions) { _, _ in
            guard let selection = selectedMachineFilter else { return }
            if machineOptions.first(where: { $0.id == selection }) == nil {
                selectedMachineFilter = nil
                applyFilters(locationId: selectedLocationFilter, machineId: nil)
            }
        }
    }

    private var hasChartData: Bool {
        stats.points.contains { !$0.machines.isEmpty }
    }

    private var shouldHideLegend: Bool {
        machineOptions.count > 6
    }

    private var maxYValue: Double {
        let maxPoint = stats.points.map { Double($0.totalItems) }.max() ?? 1
        return max(maxPoint, 1) * 1.2
    }

    private func chartDate(from string: String) -> Date? {
        Self.inputDateFormatter.date(from: string)
    }

    private func formatLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private var orderedDayLabels: [String] {
        stats.points
            .map(pointLabel(for:))
            .reducingUnique()
    }

    private static let inputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private func pointLabel(for point: SkuStatsPoint) -> String {
        if let date = chartDate(from: point.date) {
            return formatLabel(for: date)
        }
        return point.date
    }

    @ViewBuilder
    private var filterControls: some View {
        HStack {
            Menu {
                Button("All Locations") {
                    guard selectedLocationFilter != nil else { return }
                    applyFilters(locationId: nil, machineId: nil)
                }
                if !locationOptions.isEmpty {
                    Divider()
                    ForEach(locationOptions) { location in
                        Button(location.displayName) {
                            guard selectedLocationFilter != location.id else { return }
                            applyFilters(locationId: location.id, machineId: nil)
                        }
                    }
                }
            } label: {
                filterChip(label: locationFilterLabel)
            }
            .foregroundStyle(.secondary)

            Menu {
                Button("All Machines") {
                    guard selectedMachineFilter != nil else { return }
                    applyFilters(locationId: selectedLocationFilter, machineId: nil)
                }
                let machines = visibleMachines
                if !machines.isEmpty {
                    Divider()
                    ForEach(machines) { machine in
                        Button(machine.displayName) {
                            guard selectedMachineFilter != machine.id else { return }
                            applyFilters(locationId: selectedLocationFilter, machineId: machine.id)
                        }
                    }
                }
            } label: {
                filterChip(label: machineFilterLabel)
            }
            .disabled(visibleMachines.isEmpty && machineOptions.isEmpty)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func applyFilters(locationId: String?, machineId: String?) {
        Task {
            await onFilterChange(locationId, machineId)
        }
    }

    @ViewBuilder
    private var chartView: some View {
        let chart = Chart {
            ForEach(stats.points, id: \.date) { point in
                let dayLabel = pointLabel(for: point)
                if point.machines.isEmpty {
                    BarMark(
                        x: .value("Day", dayLabel),
                        y: .value("Items", 0)
                    )
                    .foregroundStyle(.gray)
                    .opacity(0.6)
                } else {
                    ForEach(point.machines) { machine in
                        let machineLabel = machine.machineName ?? machine.machineCode
                        BarMark(
                            x: .value("Day", dayLabel),
                            y: .value("Items", machine.count)
                        )
                        .foregroundStyle(by: .value("Machine", machineLabel))
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
