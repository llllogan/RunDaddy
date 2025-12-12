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
    @Published private(set) var totalRuns: Int?
    @Published private(set) var averageRunsPerDay: Double?
    @Published var recentNotesCount: Int?

    private var session: AuthSession
    private let service: RunsServicing
    private let authService: AuthServicing
    private let notesService: NotesServicing

    convenience init(session: AuthSession) {
        self.init(
            session: session,
            service: RunsService(),
            authService: AuthService(),
            notesService: NotesService()
        )
    }

    init(session: AuthSession, service: RunsServicing, authService: AuthServicing, notesService: NotesServicing) {
        self.session = session
        self.service = service
        self.authService = authService
        self.notesService = notesService
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
            async let stats = service.fetchRunStats(credentials: session.credentials)
            async let notesSummary = notesService.fetchNotes(
                runId: nil,
                includePersistentForRun: true,
                recentDays: 2,
                limit: 1,
                credentials: session.credentials
            )

            let (todayRuns, tomorrowRuns, currentUserProfile, runStats, notesResponse) = try await (today, tomorrow, profile, stats, notesSummary)
            self.todayRuns = todayRuns
            self.tomorrowRuns = tomorrowRuns
            self.currentUserProfile = currentUserProfile
            totalRuns = runStats.totalRuns
            averageRunsPerDay = runStats.averageRunsPerDay
            recentNotesCount = notesResponse.total
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
            totalRuns = nil
            averageRunsPerDay = nil
            recentNotesCount = nil
        }

        isLoading = false
    }

    func updateSession(_ session: AuthSession) {
        self.session = session
    }


}
