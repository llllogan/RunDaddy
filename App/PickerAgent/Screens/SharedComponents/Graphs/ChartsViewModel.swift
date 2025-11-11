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
    @Published var dailyInsightsLookbackDays = 7
    @Published var topLocations: [TopLocations.Location] = []
    @Published var isLoadingTopLocations = false
    @Published var topLocationsError: String?
    @Published var topLocationsLookbackDays = 30
    @Published var packPeriodComparisons: [PackPeriodComparisons.PeriodComparison] = []
    @Published var isLoadingPeriodComparisons = false
    @Published var packPeriodComparisonsError: String?

    private var session: AuthSession
    private let analyticsService: AnalyticsServicing

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
        async let comparisonsTask: Void = loadPeriodComparisons()
        _ = await (insightsTask, topLocationsTask, comparisonsTask)
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
}
