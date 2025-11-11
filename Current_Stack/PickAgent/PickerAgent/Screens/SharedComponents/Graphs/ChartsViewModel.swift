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
    @Published var dailyInsightsLookbackDays = 30

    private let session: AuthSession
    private let analyticsService: AnalyticsServicing

    init(session: AuthSession, analyticsService: AnalyticsServicing = AnalyticsService()) {
        self.session = session
        self.analyticsService = analyticsService
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
}
