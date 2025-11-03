//
//  LocationsService.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import Foundation

class LocationsService {
    func fetchLocations() async throws -> [APILocation] {
        let authService = AuthService()

        let url = URL(string: "\(APIConfig.baseURL)/locations")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await authService.performAuthenticatedRequest(request)

        guard response.statusCode == 200 else {
            throw LocationsError.fetchFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let locations = try decoder.decode([APILocation].self, from: data)

        return locations
    }

    func fetchLocation(id: String) async throws -> APILocation {
        let authService = AuthService()

        let url = URL(string: "\(APIConfig.baseURL)/locations/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await authService.performAuthenticatedRequest(request)

        guard response.statusCode == 200 else {
            throw LocationsError.fetchFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let location = try decoder.decode(APILocation.self, from: data)

        return location
    }
}

enum LocationsError: Error {
    case invalidResponse
    case fetchFailed
}