//
//  RunsService.swift
//  PickAgent
//
//  Created by ChatGPT on 5/24/2025.
//

import Foundation

protocol RunsServicing {
    func fetchRuns(for schedule: RunsSchedule, credentials: AuthCredentials) async throws -> [RunSummary]
    func fetchRunStats(credentials: AuthCredentials) async throws -> RunStats
    func fetchAllRuns(credentials: AuthCredentials) async throws -> [RunSummary]
    func fetchRunDetail(withId runId: String, credentials: AuthCredentials) async throws -> RunDetail
    func assignUser(to runId: String, userId: String, role: String, credentials: AuthCredentials) async throws
    func fetchCompanyUsers(credentials: AuthCredentials) async throws -> [CompanyUser]
    func updatePickItemStatuses(runId: String, pickIds: [String], isPicked: Bool, credentials: AuthCredentials) async throws
    func deletePickItem(runId: String, pickId: String, credentials: AuthCredentials) async throws
    func deletePickEntries(for runId: String, locationID: String, credentials: AuthCredentials) async throws
    func updateRunStatus(runId: String, status: String, credentials: AuthCredentials) async throws
    func fetchChocolateBoxes(for runId: String, credentials: AuthCredentials) async throws -> [RunDetail.ChocolateBox]
    func createChocolateBox(for runId: String, number: Int, machineId: String, credentials: AuthCredentials) async throws -> RunDetail.ChocolateBox
    func updateChocolateBox(for runId: String, boxId: String, number: Int?, machineId: String?, credentials: AuthCredentials) async throws -> RunDetail.ChocolateBox
    func deleteChocolateBox(for runId: String, boxId: String, credentials: AuthCredentials) async throws
    func updateSkuFreshStatus(skuId: String, isFreshOrFrozen: Bool, credentials: AuthCredentials) async throws
    func updateSkuCountPointer(skuId: String, countNeededPointer: String, credentials: AuthCredentials) async throws
    func deleteRun(runId: String, credentials: AuthCredentials) async throws
    func createPackingSession(for runId: String, categories: [String?]?, credentials: AuthCredentials) async throws -> PackingSession
    func fetchActivePackingSession(for runId: String, credentials: AuthCredentials) async throws -> PackingSession?
    func abandonPackingSession(runId: String, packingSessionId: String, credentials: AuthCredentials) async throws -> AbandonedPackingSession
    func finishPackingSession(runId: String, packingSessionId: String, credentials: AuthCredentials) async throws -> FinishedPackingSession
    func fetchAudioCommands(for runId: String, packingSessionId: String, credentials: AuthCredentials) async throws -> AudioCommandsResponse
    func updateLocationOrder(for runId: String, orderedLocationIds: [String?], credentials: AuthCredentials) async throws -> [RunDetail.LocationOrder]
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

    struct ChocolateBox: Identifiable, Equatable {
        let id: String
        let number: Int
        let machine: Machine?
    }
    
    struct Machine: Identifiable, Equatable {
        let id: String
        let code: String
        let description: String?
        let machineType: MachineType?
        let location: Location?
    }
    
    struct MachineType: Identifiable, Equatable {
        let id: String
        let name: String
        let description: String?
    }
    
    struct Location: Identifiable, Equatable {
        let id: String
        let name: String?
        let address: String?
    }

    let id: String
    let status: String
    let scheduledFor: Date?
    let pickingStartedAt: Date?
    let pickingEndedAt: Date?
    let createdAt: Date
    let locationCount: Int
    let chocolateBoxes: [ChocolateBox]
    let runner: Participant?

    var statusDisplay: String {
        status
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
    
    var chocolateBoxesDisplay: String {
        let count = chocolateBoxes.count
        return count == 1 ? "1 chocolate box" : "\(count) chocolate boxes"
    }
}

typealias RunParticipant = RunSummary.Participant

struct RunStats: Equatable {
    let totalRuns: Int
    let averageRunsPerDay: Double
}

struct AudioCommandsResponse: Equatable, Decodable {
    struct AudioCommand: Equatable, Decodable {
        let id: String
        let audioCommand: String
        let pickEntryIds: [String]
        let type: String // 'location', 'machine', or 'item'
        let locationId: String?
        let locationName: String?
        let locationAddress: String?
        let machineName: String?
        let machineId: String?
        let machineCode: String?
        let machineDescription: String?
        let machineTypeName: String?
        let skuName: String?
        let skuCode: String?
        let count: Int
        let coilCode: String?
        let coilCodes: [String]? // Array of all coil codes for UI display
        let order: Int
    }

    let runId: String
    let audioCommands: [AudioCommand]
    let totalItems: Int
    let hasItems: Bool
}

struct RunDetail: Equatable {
    struct Location: Identifiable, Equatable {
        let id: String
        let name: String?
        let address: String?
        let openingTimeMinutes: Int?
        let closingTimeMinutes: Int?
        let dwellTimeMinutes: Int?

        init(
            id: String,
            name: String?,
            address: String?,
            openingTimeMinutes: Int? = nil,
            closingTimeMinutes: Int? = nil,
            dwellTimeMinutes: Int? = nil
        ) {
            self.id = id
            self.name = name
            self.address = address
            self.openingTimeMinutes = openingTimeMinutes
            self.closingTimeMinutes = closingTimeMinutes
            self.dwellTimeMinutes = dwellTimeMinutes
        }
    }

    struct MachineTypeDescriptor: Equatable {
        let id: String
        let name: String
        let description: String?
    }

    struct Machine: Identifiable, Equatable {
        let id: String
        let code: String
        let description: String?
        let machineType: MachineTypeDescriptor?
        let location: Location?
    }

    struct Packer: Identifiable, Equatable {
        let id: String
        let firstName: String?
        let lastName: String?
        let email: String?
        let sessionCount: Int

        var displayName: String {
            let trimmedFirst = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trimmedLast = lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !trimmedFirst.isEmpty && !trimmedLast.isEmpty {
                return "\(trimmedFirst) \(trimmedLast)"
            } else if !trimmedFirst.isEmpty {
                return trimmedFirst
            } else if !trimmedLast.isEmpty {
                return trimmedLast
            } else {
                return email ?? "Unknown Picker"
            }
        }
    }

    struct Sku: Equatable {
        let id: String
        let code: String
        let name: String
        let type: String
        let category: String?
        let weight: Double?
        let labelColour: String?
        let isFreshOrFrozen: Bool
        let countNeededPointer: String?
    }

    struct Coil: Equatable {
        let id: String
        let code: String
        let machineId: String?
    }

    struct CoilItem: Equatable {
        let id: String
        let par: Int
        let coil: Coil
    }

    struct PickItem: Identifiable, Equatable {
        let id: String
        let count: Int
        let current: Int?
        let par: Int?
        let need: Int?
        let forecast: Int?
        let total: Int?
        let isPicked: Bool
        let pickedAt: Date?
        let coilItem: CoilItem
        let sku: Sku?
        let machine: Machine?
        let location: Location?
        let packingSessionId: String?

        var isInPackingSession: Bool {
            guard let packedId = packingSessionId?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !packedId.isEmpty
        }
        
        func countForPointer(_ pointer: String) -> Int? {
            switch pointer.lowercased() {
            case "current": return current
            case "par": return par
            case "need": return need
            case "forecast": return forecast
            case "total": return total
            default: return count
            }
        }
    }

    struct ChocolateBox: Identifiable, Equatable {
        let id: String
        let number: Int
        let machine: Machine?
    }

    struct LocationOrder: Identifiable, Equatable {
        let id: String
        let locationId: String?
        let position: Int
    }

    let id: String
    let status: String
    let companyId: String
    let scheduledFor: Date?
    let pickingStartedAt: Date?
    let pickingEndedAt: Date?
    let createdAt: Date
    let runner: RunParticipant?
    let locations: [Location]
    let machines: [Machine]
    let pickItems: [PickItem]
    let chocolateBoxes: [ChocolateBox]
    var locationOrders: [LocationOrder]
    let packers: [Packer]

    var runDate: Date {
        scheduledFor ?? createdAt
    }

    var pendingPickItems: [PickItem] {
        pickItems.filter { !$0.isPicked }
    }
}

struct PackingSession: Equatable, Decodable {
    let id: String
    let runId: String
    let userId: String
    let startedAt: Date
    let finishedAt: Date?
    let status: String
    let assignedPickEntries: Int?
}

private struct PackingSessionStartRequest: Encodable {
    let categories: [String?]?
}

struct AbandonedPackingSession: Equatable, Decodable {
    let id: String
    let status: String
    let finishedAt: Date?
    let clearedPickEntries: Int
}

struct FinishedPackingSession: Equatable, Decodable {
    let id: String
    let status: String
    let finishedAt: Date?
    let clearedPickEntries: Int
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

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let timezoneIdentifier = TimeZone.current.identifier
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "timezone", value: timezoneIdentifier))
        components?.queryItems = queryItems
        let resolvedURL = components?.url ?? url

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                // Check if this is a "no membership" error vs a real auth error
                if let responseString = String(data: data, encoding: .utf8),
                   responseString.contains("Membership") || responseString.contains("company") {
                    // User has no company membership - return empty array instead of error
                    return []
                }
                throw AuthError.unauthorized
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode([RunResponse].self, from: data)
        return payload.map { $0.toSummary() }
    }

    func fetchRunStats(credentials: AuthCredentials) async throws -> RunStats {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent("stats")

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
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

        let payload = try decoder.decode(RunStatsResponse.self, from: data)
        return RunStats(totalRuns: payload.totalRuns, averageRunsPerDay: payload.averageRunsPerDay)
    }

    func fetchAllRuns(credentials: AuthCredentials) async throws -> [RunSummary] {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent("all")

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                // Check if this is a "no membership" error vs a real auth error
                if let responseString = String(data: data, encoding: .utf8),
                   responseString.contains("Membership") || responseString.contains("company") {
                    // User has no company membership - return empty array instead of error
                    return []
                }
                throw AuthError.unauthorized
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode([RunResponse].self, from: data)
        return payload.map { $0.toSummary() }
    }

    func fetchRunDetail(withId runId: String, credentials: AuthCredentials) async throws -> RunDetail {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)

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
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.packingSessionNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(RunDetailResponse.self, from: data)
        return payload.toDetail()
    }

    func assignUser(to runId: String, userId: String, role: String, credentials: AuthCredentials) async throws {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("assignment")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = userId.isEmpty ? ["role": role] : ["userId": userId, "role": role]
        print("Assigning user - RunID: \(runId), UserID: \(userId), Role: \(role), Body: \(body)")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw RunsServiceError.insufficientPermissions
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            if httpResponse.statusCode == 409 {
                throw RunsServiceError.roleAlreadyAssigned
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }
    }
    
    func fetchCompanyUsers(credentials: AuthCredentials) async throws -> [CompanyUser] {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("users")

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

        let payload = try decoder.decode([CompanyUserResponse].self, from: data)
        return payload.map { $0.toCompanyUser() }
    }
    
    func updatePickItemStatuses(runId: String, pickIds: [String], isPicked: Bool, credentials: AuthCredentials) async throws {
        let normalizedPickIds = Array(Set(pickIds.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
        guard !normalizedPickIds.isEmpty else { return }

        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("picks")
        url.appendPathComponent("status")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "pickIds": normalizedPickIds,
            "isPicked": isPicked
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.pickItemNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }
    }
    
    func deletePickItem(runId: String, pickId: String, credentials: AuthCredentials) async throws {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("picks")
        url.appendPathComponent(pickId)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.pickItemNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }
    }

    func deletePickEntries(for runId: String, locationID: String, credentials: AuthCredentials) async throws {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("locations")
        url.appendPathComponent(locationID)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw AuthError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 403 {
                throw RunsServiceError.insufficientPermissions
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }
    }
    
    func updateRunStatus(runId: String, status: String, credentials: AuthCredentials) async throws {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("status")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["status": status]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw RunsServiceError.insufficientPermissions
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }
    }
    
    func fetchChocolateBoxes(for runId: String, credentials: AuthCredentials) async throws -> [RunDetail.ChocolateBox] {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("chocolate-boxes")

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
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode([ChocolateBoxResponse].self, from: data)
        return payload.map { $0.toChocolateBox() }
    }
    
    func createChocolateBox(for runId: String, number: Int, machineId: String, credentials: AuthCredentials) async throws -> RunDetail.ChocolateBox {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("chocolate-boxes")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["number": number, "machineId": machineId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            if httpResponse.statusCode == 409 {
                throw RunsServiceError.chocolateBoxNumberExists
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(ChocolateBoxResponse.self, from: data)
        return payload.toChocolateBox()
    }
    
    func updateChocolateBox(for runId: String, boxId: String, number: Int?, machineId: String?, credentials: AuthCredentials) async throws -> RunDetail.ChocolateBox {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("chocolate-boxes")
        url.appendPathComponent(boxId)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [:]
        if let number = number {
            body["number"] = number
        }
        if let machineId = machineId {
            body["machineId"] = machineId
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            if httpResponse.statusCode == 409 {
                throw RunsServiceError.chocolateBoxNumberExists
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(ChocolateBoxResponse.self, from: data)
        return payload.toChocolateBox()
    }
    
    func deleteChocolateBox(for runId: String, boxId: String, credentials: AuthCredentials) async throws {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("chocolate-boxes")
        url.appendPathComponent(boxId)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }
    }
    
    func updateSkuFreshStatus(skuId: String, isFreshOrFrozen: Bool, credentials: AuthCredentials) async throws {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("skus")
        url.appendPathComponent(skuId)
        url.appendPathComponent("fresh-or-frozen")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["isFreshOrFrozen": isFreshOrFrozen]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw RunsServiceError.insufficientPermissions
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }
    }
    
    func updateSkuCountPointer(skuId: String, countNeededPointer: String, credentials: AuthCredentials) async throws {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("skus")
        url.appendPathComponent(skuId)
        url.appendPathComponent("count-pointer")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["countNeededPointer": countNeededPointer]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw RunsServiceError.insufficientPermissions
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }
    }
    
    func deleteRun(runId: String, credentials: AuthCredentials) async throws {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw RunsServiceError.insufficientPermissions
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }
    }
    
    func createPackingSession(for runId: String, categories: [String?]?, credentials: AuthCredentials) async throws -> PackingSession {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("packing-sessions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if categories != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload = PackingSessionStartRequest(categories: categories)
            request.httpBody = try JSONEncoder().encode(payload)
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw RunsServiceError.insufficientPermissions
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(PackingSession.self, from: data)
        return payload
    }
    
    func fetchActivePackingSession(for runId: String, credentials: AuthCredentials) async throws -> PackingSession? {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("packing-sessions")
        url.appendPathComponent("active")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return nil
        }
        
        if httpResponse.statusCode == 304 {
            // No change; let caller decide how to handle
            return nil
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw RunsServiceError.insufficientPermissions
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(PackingSession.self, from: data)
        return payload
    }
    
    func abandonPackingSession(runId: String, packingSessionId: String, credentials: AuthCredentials) async throws -> AbandonedPackingSession {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("packing-sessions")
        url.appendPathComponent(packingSessionId)
        url.appendPathComponent("abandon")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
            if httpResponse.statusCode == 403 {
                throw RunsServiceError.insufficientPermissions
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.packingSessionNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(AbandonedPackingSession.self, from: data)
        return payload
    }
    
    func finishPackingSession(runId: String, packingSessionId: String, credentials: AuthCredentials) async throws -> FinishedPackingSession {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("packing-sessions")
        url.appendPathComponent(packingSessionId)
        url.appendPathComponent("finish")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
            if httpResponse.statusCode == 403 {
                throw RunsServiceError.insufficientPermissions
            }
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.packingSessionNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(FinishedPackingSession.self, from: data)
        return payload
    }
    
    func fetchAudioCommands(for runId: String, packingSessionId: String, credentials: AuthCredentials) async throws -> AudioCommandsResponse {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("audio-commands")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "packingSessionId", value: packingSessionId))
        components?.queryItems = queryItems
        let resolvedURL = components?.url ?? url

        var request = URLRequest(url: resolvedURL)
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
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        let payload = try decoder.decode(AudioCommandsResponse.self, from: data)
        return payload
    }

    func updateLocationOrder(for runId: String, orderedLocationIds: [String?], credentials: AuthCredentials) async throws -> [RunDetail.LocationOrder] {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("location-order")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let locationsPayload: [[String: Any]] = orderedLocationIds.enumerated().map { index, identifier in
            var entry: [String: Any] = ["order": index]
            entry["locationId"] = identifier ?? NSNull()
            return entry
        }

        let body: [String: Any] = [
            "locations": locationsPayload
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunsServiceError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw AuthError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 400 {
                throw RunsServiceError.invalidLocationOrder
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }

        struct UpdateLocationOrderResponse: Decodable {
            let locationOrders: [RunDetailResponse.LocationOrder]
        }

        let payload = try decoder.decode(UpdateLocationOrderResponse.self, from: data)
        return payload.locationOrders.map { $0.toLocationOrder() }.sorted { $0.position < $1.position }
    }
}

private struct RunStatsResponse: Decodable {
    let totalRuns: Int
    let averageRunsPerDay: Double
}

private struct RunResponse: Decodable {
    struct Participant: Decodable {
        let id: String
        let firstName: String?
        let lastName: String?
    }
    
    struct ChocolateBox: Decodable {
        let id: String
        let number: Int
        let machine: Machine?
    }
    
    struct Machine: Decodable {
        let id: String
        let code: String
        let description: String?
        let machineType: MachineType?
        let location: Location?
    }
    
    struct MachineType: Decodable {
        let id: String
        let name: String
        let description: String?
    }
    
    struct Location: Decodable {
        let id: String
        let name: String?
        let address: String?
    }

    let id: String
    let status: String
    let scheduledFor: Date?
    let pickingStartedAt: Date?
    let pickingEndedAt: Date?
    let createdAt: Date
    let locationCount: Int?
    let chocolateBoxes: [ChocolateBox]
    let runnerId: String?
    let runner: Participant?

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case scheduledFor
        case pickingStartedAt
        case pickingEndedAt
        case createdAt
        case locationCount
        case chocolateBoxes
        case runnerId
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
            chocolateBoxes: chocolateBoxes.map { box in
                RunSummary.ChocolateBox(
                    id: box.id,
                    number: box.number,
                    machine: box.machine.map { machine in
                        RunSummary.Machine(
                            id: machine.id,
                            code: machine.code,
                            description: machine.description,
                            machineType: machine.machineType.map { type in
                                RunSummary.MachineType(
                                    id: type.id,
                                    name: type.name,
                                    description: type.description
                                )
                            },
                            location: machine.location.map { location in
                                RunSummary.Location(
                                    id: location.id,
                                    name: location.name,
                                    address: location.address
                                )
                            }
                        )
                    }
                )
            },
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

private struct RunDetailResponse: Decodable {
    struct Participant: Decodable {
        let id: String
        let firstName: String?
        let lastName: String?

        func toParticipant() -> RunParticipant {
            RunParticipant(id: id, firstName: firstName, lastName: lastName)
        }
    }

    struct Location: Decodable {
        let id: String
        let name: String?
        let address: String?
        let openingTimeMinutes: Int?
        let closingTimeMinutes: Int?
        let dwellTimeMinutes: Int?

        func toLocation() -> RunDetail.Location {
            RunDetail.Location(
                id: id,
                name: name,
                address: address,
                openingTimeMinutes: openingTimeMinutes,
                closingTimeMinutes: closingTimeMinutes,
                dwellTimeMinutes: dwellTimeMinutes
            )
        }
    }

    struct MachineType: Decodable {
        let id: String
        let name: String
        let description: String?

        func toMachineType() -> RunDetail.MachineTypeDescriptor {
            RunDetail.MachineTypeDescriptor(id: id, name: name, description: description)
        }
    }

    struct Machine: Decodable {
        let id: String
        let code: String
        let description: String?
        let machineType: MachineType?
        let location: Location?

        func toMachine() -> RunDetail.Machine {
            RunDetail.Machine(
                id: id,
                code: code,
                description: description,
                machineType: machineType?.toMachineType(),
                location: location?.toLocation()
            )
        }
    }

    struct Sku: Decodable {
        let id: String
        let code: String
        let name: String
        let type: String
        let category: String?
        let weight: Double?
        let labelColour: String?
        let isFreshOrFrozen: Bool
        let countNeededPointer: String?

        func toSku() -> RunDetail.Sku {
            RunDetail.Sku(
                id: id,
                code: code,
                name: name,
                type: type,
                category: category,
                weight: weight,
                labelColour: labelColour,
                isFreshOrFrozen: isFreshOrFrozen,
                countNeededPointer: countNeededPointer
            )
        }
    }

    struct Coil: Decodable {
        let id: String
        let code: String
        let machineId: String?

        func toCoil() -> RunDetail.Coil {
            RunDetail.Coil(id: id, code: code, machineId: machineId)
        }
    }

    struct CoilItem: Decodable {
        let id: String
        let par: Int

        func toCoilItem(with coil: RunDetail.Coil) -> RunDetail.CoilItem {
            RunDetail.CoilItem(id: id, par: par, coil: coil)
        }
    }

    struct PickItem: Decodable {
        let id: String
        let count: Int
        let current: Int?
        let par: Int?
        let need: Int?
        let forecast: Int?
        let total: Int?
        let isPicked: Bool
        let pickedAt: Date?
        let coilItem: CoilItem
        let coil: Coil
        let sku: Sku?
        let machine: Machine?
        let location: Location?
        let packingSessionId: String?

        func toPickItem() -> RunDetail.PickItem {
            let coilDomain = coil.toCoil()
            return RunDetail.PickItem(
                id: id,
                count: count,
                current: current,
                par: par,
                need: need,
                forecast: forecast,
                total: total,
                isPicked: isPicked,
                pickedAt: pickedAt,
                coilItem: coilItem.toCoilItem(with: coilDomain),
                sku: sku?.toSku(),
                machine: machine?.toMachine(),
                location: location?.toLocation(),
                packingSessionId: packingSessionId
            )
        }
    }

    struct ChocolateBox: Decodable {
        let id: String
        let number: Int
        let machine: Machine?

        func toChocolateBox() -> RunDetail.ChocolateBox {
            RunDetail.ChocolateBox(id: id, number: number, machine: machine?.toMachine())
        }
    }

    struct LocationOrder: Decodable {
        let id: String
        let locationId: String?
        let position: Int

        func toLocationOrder() -> RunDetail.LocationOrder {
            RunDetail.LocationOrder(id: id, locationId: locationId, position: position)
        }
    }

    struct Packer: Decodable {
        let id: String
        let firstName: String?
        let lastName: String?
        let email: String?
        let sessionCount: Int

        func toPacker() -> RunDetail.Packer {
            RunDetail.Packer(
                id: id,
                firstName: firstName,
                lastName: lastName,
                email: email,
                sessionCount: sessionCount
            )
        }
    }

    let id: String
    let status: String
    let companyId: String
    let scheduledFor: Date?
    let pickingStartedAt: Date?
    let pickingEndedAt: Date?
    let createdAt: Date
    let runner: Participant?
    let locations: [Location]
    let machines: [Machine]
    let pickItems: [PickItem]
    let chocolateBoxes: [ChocolateBox]
    let locationOrders: [LocationOrder]
    let packers: [Packer]?

    func toDetail() -> RunDetail {
        RunDetail(
            id: id,
            status: status,
            companyId: companyId,
            scheduledFor: scheduledFor,
            pickingStartedAt: pickingStartedAt,
            pickingEndedAt: pickingEndedAt,
            createdAt: createdAt,
            runner: runner?.toParticipant(),
            locations: locations.map { $0.toLocation() },
            machines: machines.map { $0.toMachine() },
            pickItems: pickItems.filter { $0.count > 0 }.map { $0.toPickItem() },
            chocolateBoxes: chocolateBoxes.map { $0.toChocolateBox() },
            locationOrders: locationOrders.map { $0.toLocationOrder() }.sorted { $0.position < $1.position },
            packers: (packers ?? []).map { $0.toPacker() }
        )
    }
}

private struct ChocolateBoxResponse: Decodable {
    let id: String
    let number: Int
    let machine: RunDetailResponse.Machine?

    func toChocolateBox() -> RunDetail.ChocolateBox {
        RunDetail.ChocolateBox(id: id, number: number, machine: machine?.toMachine())
    }
}

private struct CompanyUserResponse: Decodable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    let phone: String?
    let role: String?
    
    func toCompanyUser() -> CompanyUser {
        CompanyUser(
            id: id,
            email: email,
            firstName: firstName,
            lastName: lastName,
            phone: phone,
            role: role
        )
    }
}

enum RunsServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case runNotFound
    case pickItemNotFound
    case insufficientPermissions
    case roleAlreadyAssigned
    case chocolateBoxNumberExists
    case packingSessionNotFound
    case invalidLocationOrder

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't connect to RunDaddy right now. Please try again."
        case let .serverError(code):
            return "Fetching runs failed with an unexpected error (code \(code))."
        case .runNotFound:
            return "We couldn't find details for that run. It may have been removed."
        case .pickItemNotFound:
            return "We couldn't find that pick entry. It may have already been removed."
        case .insufficientPermissions:
            return "You don't have permission to perform this action."
        case .roleAlreadyAssigned:
            return "This role is already assigned to another user."
        case .chocolateBoxNumberExists:
            return "This chocolate box number already exists for this run."
        case .packingSessionNotFound:
            return "We couldn't find that packing session for this run. Please try starting again."
        case .invalidLocationOrder:
            return "We couldn't determine which locations to reorder. Please try again."
        }
    }
}
