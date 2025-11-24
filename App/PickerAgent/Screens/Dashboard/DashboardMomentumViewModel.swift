//
//  DashboardMomentumViewModel.swift
//  PickAgent
//
//  Created by ChatGPT on 5/25/2025.
//

import Foundation
import Combine

@MainActor
final class DashboardMomentumViewModel: ObservableObject {
    @Published private(set) var snapshot: DashboardMomentumSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var pickEntryBreakdown: PickEntryBreakdown?
    @Published private(set) var isLoadingBreakdown = false
    @Published private(set) var breakdownError: String?

    private var session: AuthSession
    private let analyticsService: AnalyticsServicing
    private let dashboardAggregation: PickEntryBreakdown.Aggregation = .week
    private let dashboardPeriods: Int = 2

    init(session: AuthSession, analyticsService: AnalyticsServicing? = nil) {
        self.session = session
        self.analyticsService = analyticsService ?? AnalyticsService()
    }

    func loadSnapshot(force: Bool = false) async {
        if isLoading && !force {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await analyticsService.fetchDashboardMomentum(credentials: session.credentials)
            snapshot = response
            errorMessage = nil
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let analyticsError = error as? AnalyticsServiceError {
                errorMessage = analyticsError.localizedDescription
            } else {
                errorMessage = "We couldn't load momentum data right now."
            }
        }
    }

    func loadPickEntryBreakdown(force: Bool = false) async {
        if isLoadingBreakdown && !force {
            return
        }

        isLoadingBreakdown = true
        defer { isLoadingBreakdown = false }

        do {
            let breakdown = try await analyticsService.fetchPickEntryBreakdown(
                aggregation: dashboardAggregation,
                periods: dashboardPeriods,
                credentials: session.credentials
            )
            pickEntryBreakdown = breakdown
            breakdownError = nil
        } catch {
            if let authError = error as? AuthError {
                breakdownError = authError.localizedDescription
            } else if let analyticsError = error as? AnalyticsServiceError {
                breakdownError = analyticsError.localizedDescription
            } else {
                breakdownError = "We couldn't load pick entry history right now."
            }
        }
    }

    func updateSession(_ session: AuthSession) {
        self.session = session
    }
}
