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
    private var aggregation: PickEntryBreakdown.Aggregation { selectedPeriod.pickEntryAggregation }
    private var calendar: Calendar { chartCalendar(for: stats.timeZone) }

    private var visibleMachines: [SkuStatsMachineOption] {
        guard let locationId = selectedLocationFilter else {
            return machineOptions
        }
        return machineOptions.filter { $0.locationId == locationId }
    }

    private var breakdownPoints: [PickEntryBreakdown.Point] {
        let mappedPoints: [PickEntryBreakdown.Point] = stats.points.compactMap { point in
            guard let start = parseAnalyticsDay(point.date, timeZoneIdentifier: stats.timeZone) else { return nil }
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let segments = point.machines.map { machine in
                PickEntryBreakdown.Segment(
                    skuId: machine.machineId,
                    skuCode: machine.machineCode,
                    skuName: machine.machineName ?? machine.machineCode,
                    totalItems: machine.count
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
            return mappedPoints.sorted { $0.start < $1.start }
        }

        return ensureRollingEightDayWindow(points: mappedPoints, calendar: calendar)
    }

    private var weekAverages: [PickEntryBreakdown.WeekAverage] {
        guard aggregation == .week else { return [] }
        return buildWeekAverages(from: breakdownPoints, calendar: calendar)
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
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
            }

            filterControls

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
        breakdownPoints.contains { !$0.skus.isEmpty }
    }

    private var chartMachineCount: Int {
        let machineIds = breakdownPoints.flatMap { point in
            point.skus.map(\.skuId)
        }
        return Set(machineIds).count
    }

    private var shouldHideLegend: Bool {
        chartMachineCount > 6
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
}
