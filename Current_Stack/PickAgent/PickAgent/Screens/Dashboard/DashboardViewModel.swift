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
    @Published private(set) var runsToPack: [RunSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentUserProfile: CurrentUserProfile?

    private let session: AuthSession
    private let service: RunsServicing
    private let authService: AuthServicing

    convenience init(session: AuthSession) {
        self.init(session: session, service: RunsService(), authService: AuthService())
    }

    init(session: AuthSession, service: RunsServicing, authService: AuthServicing) {
        self.session = session
        self.service = service
        self.authService = authService
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
            let (todayRuns, runsToPack, currentUserProfile) = try await (today, tomorrow, profile)
            self.todayRuns = todayRuns
            self.runsToPack = runsToPack
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
            runsToPack = []
        }

        isLoading = false
    }
}
