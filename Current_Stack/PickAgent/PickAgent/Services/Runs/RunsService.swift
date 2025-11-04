//
//  RunsService.swift
//  PickAgent
//
//  Created by ChatGPT on 5/24/2025.
//

import Foundation

protocol RunsServicing {
    func fetchRuns(for schedule: RunsSchedule, credentials: AuthCredentials) async throws -> [RunSummary]
}

enum RunsSchedule {
    case today
    case tomorrow

    var pathComponent: String {
        switch self {
        case .today:
            return "today"
        case .tomorrow:
            return "tomorrow"
        }
    }
}

struct RunSummary: Identifiable, Equatable {
    struct Participant: Equatable {
        let id: String
        let firstName: String?
        let lastName: String?

        var displayName: String? {
            let trimmedFirst = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trimmedLast = lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !trimmedFirst.isEmpty {
                return trimmedFirst
            }
            if !trimmedLast.isEmpty {
                return trimmedLast
            }
            return nil
        }
    }

    let id: String
    let status: String
    let scheduledFor: Date?
    let pickingStartedAt: Date?
    let pickingEndedAt: Date?
    let createdAt: Date
    let locationCount: Int
    let picker: Participant?
    let runner: Participant?

    var statusDisplay: String {
        status
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

final class RunsService: RunsServicing {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchRuns(for schedule: RunsSchedule, credentials: AuthCredentials) async throws -> [RunSummary] {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(schedule.pathComponent)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode([RunResponse].self, from: data)
        return payload.map { $0.toSummary() }
    }
}

private struct RunResponse: Decodable {
    struct Participant: Decodable {
        let id: String
        let firstName: String?
        let lastName: String?
    }

    let id: String
    let status: String
    let scheduledFor: Date?
    let pickingStartedAt: Date?
    let pickingEndedAt: Date?
    let createdAt: Date
    let locationCount: Int?
    let pickerId: String?
    let runnerId: String?
    let picker: Participant?
    let runner: Participant?

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case scheduledFor
        case pickingStartedAt
        case pickingEndedAt
        case createdAt
        case locationCount
        case pickerId
        case runnerId
        case picker
        case runner
    }

    func toSummary() -> RunSummary {
        RunSummary(
            id: id,
            status: status,
            scheduledFor: scheduledFor,
            pickingStartedAt: pickingStartedAt,
            pickingEndedAt: pickingEndedAt,
            createdAt: createdAt,
            locationCount: locationCount ?? 0,
            picker: resolvedParticipant(from: picker, fallbackID: pickerId),
            runner: resolvedParticipant(from: runner, fallbackID: runnerId)
        )
    }

    private func resolvedParticipant(from response: Participant?, fallbackID: String?) -> RunSummary.Participant? {
        if let response {
            return RunSummary.Participant(
                id: response.id,
                firstName: response.firstName,
                lastName: response.lastName
            )
        }

        guard let fallbackID else {
            return nil
        }

        return RunSummary.Participant(id: fallbackID, firstName: nil, lastName: nil)
    }
}

enum RunsServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't connect to RunDaddy right now. Please try again."
        case let .serverError(code):
            return "Fetching runs failed with an unexpected error (code \(code))."
        }
    }
}
