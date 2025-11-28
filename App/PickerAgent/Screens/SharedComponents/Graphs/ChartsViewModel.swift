//
//  ChartsViewModel.swift
//  PickAgent
//
//  Created by Logan Janssen on 4/11/2025.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ChartsViewModel: ObservableObject {
    @Published var dailyInsights: [DailyInsights.Point] = []
    @Published var isLoadingInsights = false
    @Published var insightsError: String?
    @Published var dailyInsightsLookbackDays = 8
    @Published var topLocations: [TopLocations.Location] = []
    @Published var isLoadingTopLocations = false
    @Published var topLocationsError: String?
    @Published var topLocationsLookbackDays = 30
    @Published var topSkuStats: TopSkuStats?
    @Published var isLoadingTopSkus = false
    @Published var topSkusError: String?
    @Published var topSkuLookbackDays = 365
    @Published var skuBreakdownPoints: [PickEntryBreakdown.Point] = []
    @Published var isLoadingSkuBreakdown = false
    @Published var skuBreakdownError: String?
    @Published var skuBreakdownAggregation: PickEntryBreakdown.Aggregation = .week
    @Published var skuBreakdownShowBars: Int = PickEntryBreakdown.Aggregation.week.defaultBars
    @Published var skuBreakdownWeekAverages: [PickEntryBreakdown.WeekAverage] = []
    @Published var skuBreakdownTimeZone = TimeZone.current.identifier
    @Published var skuBreakdownFocus = PickEntryBreakdown.ChartItemFocus(skuId: nil, machineId: nil, locationId: nil)
    @Published var skuBreakdownFilters = PickEntryBreakdown.Filters(skuIds: [], machineIds: [], locationIds: [])
    @Published var skuBreakdownAvailableFilters = PickEntryBreakdown.AvailableFilters(sku: [], machine: [], location: [])
    @Published var packPeriodComparisons: [PackPeriodComparisons.PeriodComparison] = []
    @Published var isLoadingPeriodComparisons = false
    @Published var packPeriodComparisonsError: String?
    @Published var machinePickTotals: [DashboardMomentumSnapshot.MachineSlice] = []
    @Published var isLoadingMachinePickTotals = false
    @Published var machinePickTotalsError: String?
    @Published var machineTouches: [DashboardMomentumSnapshot.MachineTouchPoint] = []
    @Published var isLoadingMachineTouches = false
    @Published var machineTouchesError: String?

    private var session: AuthSession
    private let analyticsService: AnalyticsServicing
    private var lastTopSkuLocationId: String?
    private var lastTopSkuMachineId: String?

    init(session: AuthSession, analyticsService: AnalyticsServicing? = nil) {
        self.session = session
        self.analyticsService = analyticsService ?? AnalyticsService()
    }

    func updateSession(_ session: AuthSession) {
        guard self.session != session else { return }
        self.session = session
        Task { [weak self] in
            await self?.refreshAllCharts()
        }
    }

    func refreshAllCharts() async {
        async let insightsTask: Void = loadDailyInsights()
        async let topLocationsTask: Void = loadTopLocations()
        async let topSkusTask: Void = loadTopSkus(locationId: lastTopSkuLocationId, machineId: lastTopSkuMachineId)
        async let comparisonsTask: Void = loadPeriodComparisons()
        async let machineTotalsTask: Void = loadMachinePickTotals()
        async let skuBreakdownTask: Void = loadSkuBreakdown(
            aggregation: skuBreakdownAggregation,
            showBars: skuBreakdownShowBars
        )
        _ = await (insightsTask, topLocationsTask, topSkusTask, comparisonsTask, machineTotalsTask, skuBreakdownTask)
    }

    func loadDailyInsights() async {
        isLoadingInsights = true
        insightsError = nil

        do {
            let response = try await analyticsService.fetchDailyInsights(
                lookbackDays: dailyInsightsLookbackDays,
                credentials: session.credentials
            )
            dailyInsights = response.points
        } catch let authError as AuthError {
            insightsError = authError.localizedDescription
            dailyInsights = []
        } catch let analyticsError as AnalyticsServiceError {
            insightsError = analyticsError.localizedDescription
            dailyInsights = []
        } catch {
            insightsError = "We couldn't load insights right now. Please try again."
            dailyInsights = []
        }

        isLoadingInsights = false
    }

    func updateLookbackDays(_ days: Int) {
        dailyInsightsLookbackDays = days
        Task {
            await loadDailyInsights()
        }
    }

    func refreshInsights() async {
        await loadDailyInsights()
    }

    func loadTopLocations() async {
        isLoadingTopLocations = true
        topLocationsError = nil

        do {
            let response = try await analyticsService.fetchTopLocations(
                lookbackDays: topLocationsLookbackDays,
                credentials: session.credentials
            )
            topLocations = response.locations
            topLocationsLookbackDays = response.lookbackDays
        } catch let authError as AuthError {
            topLocationsError = authError.localizedDescription
            topLocations = []
        } catch let analyticsError as AnalyticsServiceError {
            topLocationsError = analyticsError.localizedDescription
            topLocations = []
        } catch {
            topLocationsError = "We couldn't load locations right now. Please try again."
            topLocations = []
        }

        isLoadingTopLocations = false
    }

    func updateTopLocationsLookbackDays(_ days: Int) {
        topLocationsLookbackDays = days
        Task {
            await loadTopLocations()
        }
    }

    func refreshTopLocations() async {
        await loadTopLocations()
    }

    func loadTopSkus(locationId: String?, machineId: String?) async {
        isLoadingTopSkus = true
        topSkusError = nil

        do {
            let response = try await analyticsService.fetchTopSkus(
                lookbackDays: topSkuLookbackDays,
                locationId: locationId,
                machineId: machineId,
                credentials: session.credentials
            )
            topSkuStats = response
            topSkuLookbackDays = response.lookbackDays
            lastTopSkuLocationId = response.appliedLocationId
            lastTopSkuMachineId = response.appliedMachineId
            isLoadingTopSkus = false
            return
        } catch let authError as AuthError {
            topSkusError = authError.localizedDescription
            topSkuStats = nil
        } catch let analyticsError as AnalyticsServiceError {
            topSkusError = analyticsError.localizedDescription
            topSkuStats = nil
        } catch {
            topSkusError = "We couldn't load SKUs right now. Please try again."
            topSkuStats = nil
        }

        isLoadingTopSkus = false
    }

    func refreshTopSkus() async {
        await loadTopSkus(locationId: lastTopSkuLocationId, machineId: lastTopSkuMachineId)
    }

    func loadSkuBreakdown(
        aggregation: PickEntryBreakdown.Aggregation? = nil,
        showBars: Int? = nil,
        focus: PickEntryBreakdown.ChartItemFocus? = nil,
        filters: PickEntryBreakdown.Filters? = nil
    ) async {
        if isLoadingSkuBreakdown && aggregation == nil && showBars == nil {
            return
        }

        let targetAggregation = aggregation ?? skuBreakdownAggregation
        let targetShowBars = showBars ?? skuBreakdownShowBars
        let targetFocus = focus ?? skuBreakdownFocus
        let targetFilters = filters ?? skuBreakdownFilters

        isLoadingSkuBreakdown = true
        skuBreakdownError = nil

        do {
            let response = try await analyticsService.fetchPickEntryBreakdown(
                aggregation: targetAggregation,
                focus: targetFocus,
                filters: targetFilters,
                showBars: targetShowBars,
                credentials: session.credentials
            )
            skuBreakdownTimeZone = response.timeZone
            skuBreakdownAggregation = response.aggregation
            skuBreakdownShowBars = response.showBars
            skuBreakdownPoints = response.points
            skuBreakdownWeekAverages = response.weekAverages
            skuBreakdownFocus = response.chartItemFocus
            skuBreakdownFilters = response.filters
            skuBreakdownAvailableFilters = response.availableFilters
        } catch let authError as AuthError {
            skuBreakdownError = authError.localizedDescription
            skuBreakdownPoints = []
            skuBreakdownWeekAverages = []
            skuBreakdownTimeZone = TimeZone.current.identifier
            skuBreakdownAvailableFilters = PickEntryBreakdown.AvailableFilters(sku: [], machine: [], location: [])
        } catch let analyticsError as AnalyticsServiceError {
            skuBreakdownError = analyticsError.localizedDescription
            skuBreakdownPoints = []
            skuBreakdownWeekAverages = []
            skuBreakdownTimeZone = TimeZone.current.identifier
            skuBreakdownAvailableFilters = PickEntryBreakdown.AvailableFilters(sku: [], machine: [], location: [])
        } catch {
            skuBreakdownError = "We couldn't load SKU breakdown data right now."
            skuBreakdownPoints = []
            skuBreakdownWeekAverages = []
            skuBreakdownTimeZone = TimeZone.current.identifier
            skuBreakdownAvailableFilters = PickEntryBreakdown.AvailableFilters(sku: [], machine: [], location: [])
        }

        isLoadingSkuBreakdown = false
    }

    func refreshSkuBreakdown() async {
        await loadSkuBreakdown(
            aggregation: skuBreakdownAggregation,
            showBars: skuBreakdownShowBars,
            focus: skuBreakdownFocus,
            filters: skuBreakdownFilters
        )
    }

    func updateSkuBreakdownAggregation(_ aggregation: PickEntryBreakdown.Aggregation) {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.skuBreakdownAggregation = aggregation
                self.skuBreakdownShowBars = aggregation.defaultBars
            }
            await self.loadSkuBreakdown(
                aggregation: aggregation,
                showBars: aggregation.defaultBars,
                focus: self.skuBreakdownFocus,
                filters: self.skuBreakdownFilters
            )
        }
    }

    func updateSkuBreakdownFilters(_ filters: PickEntryBreakdown.Filters) {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.skuBreakdownFilters = filters
            }
            await self.loadSkuBreakdown(
                aggregation: self.skuBreakdownAggregation,
                showBars: self.skuBreakdownShowBars,
                focus: self.skuBreakdownFocus,
                filters: filters
            )
        }
    }

    func updateSkuBreakdownFocus(_ focus: PickEntryBreakdown.ChartItemFocus) {
        skuBreakdownFocus = focus
    }

    func loadPeriodComparisons() async {
        isLoadingPeriodComparisons = true
        packPeriodComparisonsError = nil

        do {
            let response = try await analyticsService.fetchPackPeriodComparisons(
                credentials: session.credentials
            )
            packPeriodComparisons = response.periods
        } catch let authError as AuthError {
            packPeriodComparisonsError = authError.localizedDescription
            packPeriodComparisons = []
        } catch let analyticsError as AnalyticsServiceError {
            packPeriodComparisonsError = analyticsError.localizedDescription
            packPeriodComparisons = []
        } catch {
            packPeriodComparisonsError = "We couldn't load this comparison right now. Please try again."
            packPeriodComparisons = []
        }

        isLoadingPeriodComparisons = false
    }

    func refreshPeriodComparisons() async {
        await loadPeriodComparisons()
    }

    func loadMachinePickTotals() async {
        if isLoadingMachinePickTotals {
            return
        }

        isLoadingMachinePickTotals = true
        isLoadingMachineTouches = true
        machinePickTotalsError = nil
        machineTouchesError = nil

        do {
            let snapshot = try await analyticsService.fetchDashboardMomentum(credentials: session.credentials)
            machinePickTotals = snapshot.machinePickTotals
            machineTouches = snapshot.machineTouches
        } catch let authError as AuthError {
            let message = authError.localizedDescription
            machinePickTotalsError = message
            machineTouchesError = message
            machinePickTotals = []
            machineTouches = []
        } catch let analyticsError as AnalyticsServiceError {
            let message = analyticsError.localizedDescription
            machinePickTotalsError = message
            machineTouchesError = message
            machinePickTotals = []
            machineTouches = []
        } catch {
            let message = "We couldn't load machine metrics right now."
            machinePickTotalsError = message
            machineTouchesError = message
            machinePickTotals = []
            machineTouches = []
        }

        isLoadingMachinePickTotals = false
        isLoadingMachineTouches = false
    }

    func refreshMachinePickTotals() async {
        await loadMachinePickTotals()
    }
}
