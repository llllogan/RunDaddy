//
//  MachinesService.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import Foundation

class MachinesService {
    func fetchMachines() async throws -> [APIMachine] {
        let authService = AuthService()

        let url = URL(string: "\(APIConfig.baseURL)/machines")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await authService.performAuthenticatedRequest(request)

        guard response.statusCode == 200 else {
            throw MachinesError.fetchFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let machines = try decoder.decode([APIMachine].self, from: data)

        return machines
    }

    func fetchMachine(id: String) async throws -> APIMachine {
        let authService = AuthService()

        let url = URL(string: "\(APIConfig.baseURL)/machines/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await authService.performAuthenticatedRequest(request)

        guard response.statusCode == 200 else {
            throw MachinesError.fetchFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let machine = try decoder.decode(APIMachine.self, from: data)

        return machine
    }
}

enum MachinesError: Error {
    case invalidResponse
    case fetchFailed
}