//
//  DashboardViewModel.swift
//  PickAgent
//
//  Created by ChatGPT on 5/24/2025.
//

import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var todayRuns: [RunSummary] = []
    @Published private(set) var tomorrowRuns: [RunSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentUserProfile: CurrentUserProfile?
    @Published private(set) var dailyInsights: [DailyInsights.Point] = []
    @Published var dailyInsightsLookbackDays: Int = 14
    @Published private(set) var isLoadingInsights = false
    @Published private(set) var insightsError: String?

    private var session: AuthSession
    private let service: RunsServicing
    private let authService: AuthServicing
    private let analyticsService: AnalyticsServicing
    private let defaultInsightsLookbackDays = 14

    convenience init(session: AuthSession) {
        self.init(
            session: session,
            service: RunsService(),
            authService: AuthService(),
            analyticsService: AnalyticsService()
        )
    }

    init(session: AuthSession, service: RunsServicing, authService: AuthServicing, analyticsService: AnalyticsServicing) {
        self.session = session
        self.service = service
        self.authService = authService
        self.analyticsService = analyticsService
    }

    func loadRuns(force: Bool = false) async {
        if isLoading && !force {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            async let today = service.fetchRuns(for: .today, credentials: session.credentials)
            async let tomorrow = service.fetchRuns(for: .tomorrow, credentials: session.credentials)
            async let profile = authService.fetchCurrentUserProfile(credentials: session.credentials)
            let (todayRuns, tomorrowRuns, currentUserProfile) = try await (today, tomorrow, profile)
            self.todayRuns = todayRuns
            self.tomorrowRuns = tomorrowRuns
            self.currentUserProfile = currentUserProfile
        } catch {
            if let authError = error as? AuthError {
                errorMessage = authError.localizedDescription
            } else if let runError = error as? RunsServiceError {
                errorMessage = runError.localizedDescription
            } else {
                errorMessage = "We couldn't load your runs right now. Please try again."
            }
            todayRuns = []
            tomorrowRuns = []
        }

        isLoading = false

        await loadDailyInsights(force: force)
    }

    func updateSession(_ session: AuthSession) {
        self.session = session
    }

    func loadDailyInsights(force: Bool = false) async {
        if isLoadingInsights && !force {
            return
        }
        isLoadingInsights = true
        if force {
            insightsError = nil
        }

        defer { isLoadingInsights = false }

        do {
            let response = try await analyticsService.fetchDailyInsights(
                lookbackDays: dailyInsightsLookbackDays > 0 ? dailyInsightsLookbackDays : defaultInsightsLookbackDays,
                credentials: session.credentials
            )
            dailyInsights = response.points
            dailyInsightsLookbackDays = response.lookbackDays
            insightsError = nil
        } catch let authError as AuthError {
            insightsError = authError.localizedDescription
            dailyInsights = []
            dailyInsightsLookbackDays = 0
        } catch let analyticsError as AnalyticsServiceError {
            insightsError = analyticsError.localizedDescription
            dailyInsights = []
            dailyInsightsLookbackDays = 0
        } catch {
            insightsError = "We couldn't load insights right now. Please try again."
            dailyInsights = []
            dailyInsightsLookbackDays = 0
        }
    }
    
    func updateInsightsLookbackDays(_ days: Int) async {
        dailyInsightsLookbackDays = days
        await loadDailyInsights(force: true)
    }
}
