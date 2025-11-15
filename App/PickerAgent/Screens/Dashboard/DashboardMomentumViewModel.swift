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

    private var session: AuthSession
    private let analyticsService: AnalyticsServicing

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

    func updateSession(_ session: AuthSession) {
        self.session = session
    }
}
