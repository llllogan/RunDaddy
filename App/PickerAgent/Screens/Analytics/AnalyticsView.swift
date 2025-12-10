//
//  AnalyticsView.swift
//  PickAgent
//
//  Created by Logan Janssen on 11/11/2025.
//

import SwiftUI

struct AnalyticsView: View {
    let session: AuthSession
    
    @State private var chartRefreshTrigger = false
    @StateObject private var chartsViewModel: ChartsViewModel
    @State private var selectedAggregation: PickEntryBreakdown.Aggregation

    init(session: AuthSession) {
        self.session = session
        let viewModel = ChartsViewModel(session: session)
        _chartsViewModel = StateObject(wrappedValue: viewModel)
        _selectedAggregation = State(initialValue: viewModel.skuBreakdownAggregation)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Items Stocked") {
                    SkuBreakdownChartView(
                        viewModel: chartsViewModel,
                        refreshTrigger: chartRefreshTrigger,
                        showAggregationControls: false
                    )
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color(.separator).opacity(0.25))
                        )
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    BreakdownExtremaBento(
                        highMark: chartsViewModel.skuBreakdownHighMark,
                        lowMark: chartsViewModel.skuBreakdownLowMark,
                        aggregation: chartsViewModel.skuBreakdownAggregation,
                        timeZoneIdentifier: chartsViewModel.skuBreakdownTimeZone,
                        percentageChange: chartsViewModel.skuBreakdownPercentageChange,
                        periodDelta: chartsViewModel.skuBreakdownPeriodDelta
                    )
                    .padding(.top, 12)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                Section("Week-over-week Growth") {
                    WeeklyPickChangeChartView(viewModel: chartsViewModel, refreshTrigger: chartRefreshTrigger)
                        .padding(.top, 10)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                Section("Total Machines Stocked Per Week") {
                    MachineTouchesChartView(viewModel: chartsViewModel, refreshTrigger: chartRefreshTrigger)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
//                Section("Packing Pace") {
//                    PeriodComparisonChartView(viewModel: chartsViewModel, refreshTrigger: chartRefreshTrigger)
//                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
//                }
                Section("Top Locations") {
                    TopLocationsChartView(
                        viewModel: chartsViewModel,
                        refreshTrigger: chartRefreshTrigger,
                        showRangePicker: false
                    )
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                }
                Section("Top SKUs") {
                    TopSkusChartView(viewModel: chartsViewModel, refreshTrigger: chartRefreshTrigger)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
//                Section("Total Items vs Packed") {
//                    DailyInsightsChartView(viewModel: chartsViewModel, refreshTrigger: chartRefreshTrigger)
//                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
//                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(PickEntryBreakdown.Aggregation.allCases) { aggregation in
                            Button {
                                applyAggregation(aggregation)
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
                        Label(selectedAggregation.displayName, systemImage: "calendar")
                    }
                }
            }
            .refreshable {
                chartRefreshTrigger.toggle()
            }
            .onChange(of: chartsViewModel.skuBreakdownAggregation, initial: true) { _, newValue in
                if selectedAggregation != newValue {
                    selectedAggregation = newValue
                }
                if chartsViewModel.topLocationsLookbackDays != newValue.baseDays {
                    chartsViewModel.updateTopLocationsLookbackDays(newValue.baseDays)
                }
            }
            .onChange(of: session, initial: false) { _, newSession in
                chartsViewModel.updateSession(newSession)
            }
        }
    }

    private var cardBackground: some ShapeStyle {
        Color(.secondarySystemGroupedBackground)
    }

    private func applyAggregation(_ aggregation: PickEntryBreakdown.Aggregation) {
        guard aggregation != selectedAggregation ||
                chartsViewModel.topLocationsLookbackDays != aggregation.baseDays ||
                chartsViewModel.skuBreakdownAggregation != aggregation else {
            return
        }

        selectedAggregation = aggregation

        if chartsViewModel.skuBreakdownAggregation != aggregation {
            chartsViewModel.updateSkuBreakdownAggregation(aggregation)
        }

        if chartsViewModel.topLocationsLookbackDays != aggregation.baseDays {
            chartsViewModel.updateTopLocationsLookbackDays(aggregation.baseDays)
        }
    }
}

private struct BreakdownExtremaBento: View {
    let highMark: PickEntryBreakdown.Extremum?
    let lowMark: PickEntryBreakdown.Extremum?
    let aggregation: PickEntryBreakdown.Aggregation
    let timeZoneIdentifier: String
    let percentageChange: PickEntryBreakdown.PercentageChange?
    let periodDelta: PickEntryBreakdown.PeriodDelta?

    private var items: [BentoItem] {
        [
            changeCard,
            deltaCard,
            extremumCard(
                title: "High",
                extremum: highMark,
                symbolName: "arrow.up.to.line",
                tint: .green,
                isProminent: false
            ),
            extremumCard(
                title: "Low",
                extremum: lowMark,
                symbolName: "arrow.down.to.line",
                tint: .orange,
                isProminent: false
            )
        ]
    }

    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
            .listRowSeparator(.hidden)
    }

    private var changeCard: BentoItem {
        guard let percentageChange else {
            return BentoItem(
                title: "Change",
                value: "No data",
                symbolName: "arrow.left.and.right",
                symbolTint: .secondary
            )
        }

        let isUp = percentageChange.trend == "up"
        let isDown = percentageChange.trend == "down"
        let tint: Color = isUp ? .green : (isDown ? .red : .gray)
        let symbolName = isUp ? "arrow.up.forward" : (isDown ? "arrow.down.right" : "arrow.left.and.right")
        let value = String(format: "%@%.1f%%", percentageChange.value >= 0 ? "+" : "", percentageChange.value)

        return BentoItem(
            title: "Change",
            value: value,
            symbolName: symbolName,
            symbolTint: tint,
            isProminent: true
        )
    }

    private var deltaCard: BentoItem {
        guard let periodDelta else {
            return BentoItem(
                title: "Delta",
                value: "No data",
                symbolName: "plus.forwardslash.minus",
                symbolTint: .secondary
            )
        }

        let isPositive = periodDelta > 0
        let isNegative = periodDelta < 0
        let tint: Color = isPositive ? .green : (isNegative ? .red : .gray)
        let symbolName = isPositive ? "plus.circle" : (isNegative ? "minus.circle" : "equal.circle")
        let value = String(format: "%@%d", periodDelta >= 0 ? "+" : "", periodDelta)

        return BentoItem(
            title: "Delta",
            value: value,
            symbolName: symbolName,
            symbolTint: tint,
            isProminent: true
        )
    }

    private func extremumCard(
        title: String,
        extremum: PickEntryBreakdown.Extremum?,
        symbolName: String,
        tint: Color,
        isProminent: Bool
    ) -> BentoItem {
        guard let extremum else {
            return BentoItem(
                title: title,
                value: "No data",
                symbolName: symbolName,
                symbolTint: .secondary
            )
        }

        return BentoItem(
            title: title,
            value: BreakdownExtremumFormatter.valueText(for: extremum),
            subtitle: BreakdownExtremumFormatter.subtitle(
                for: extremum,
                aggregation: aggregation,
                timeZoneIdentifier: timeZoneIdentifier
            ),
            symbolName: symbolName,
            symbolTint: tint,
            isProminent: isProminent
        )
    }
}
