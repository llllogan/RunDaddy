//
//  RunsService.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import Foundation

class RunsService {
    func fetchRuns() async throws -> [APIRun] {
        let authService = AuthService()

        let url = URL(string: "\(APIConfig.baseURL)/runs/tobepicked")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await authService.performAuthenticatedRequest(request)

        guard response.statusCode == 200 else {
            throw RunsError.fetchFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let runs = try decoder.decode([APIRun].self, from: data)

        return runs
    }

    func deleteRun(id: String) async throws {
        let authService = AuthService()

        let url = URL(string: "\(APIConfig.baseURL)/runs/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await authService.performAuthenticatedRequest(request)

        guard response.statusCode == 204 else {
            throw RunsError.deleteFailed
        }
    }
}

enum RunsError: Error {
    case invalidResponse
    case fetchFailed
    case deleteFailed
}