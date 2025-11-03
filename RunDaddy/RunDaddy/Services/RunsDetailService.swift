//
//  RunsDetailService.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import Foundation

class RunsDetailService {
    func fetchRun(id: String) async throws -> APIDetailedRun {
        let authService = AuthService()

        let url = URL(string: "\(APIConfig.baseURL)/runs/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await authService.performAuthenticatedRequest(request)

        guard response.statusCode == 200 else {
            throw RunsDetailError.fetchFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let run = try decoder.decode(APIDetailedRun.self, from: data)

        return run
    }
}

enum RunsDetailError: Error {
    case invalidResponse
    case fetchFailed
}