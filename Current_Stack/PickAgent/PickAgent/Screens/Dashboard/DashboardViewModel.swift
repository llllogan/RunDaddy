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

    private let session: AuthSession
    private let service: RunsServicing

    convenience init(session: AuthSession) {
        self.init(session: session, service: RunsService())
    }

    init(session: AuthSession, service: RunsServicing) {
        self.session = session
        self.service = service
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
            let (todayRuns, runsToPack) = try await (today, tomorrow)
            self.todayRuns = todayRuns
            self.runsToPack = runsToPack
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
