//
//  RunsService.swift
//  PickAgent
//
//  Created by ChatGPT on 5/24/2025.
//

import Foundation

protocol RunsServicing {
    func fetchRuns(for schedule: RunsSchedule, credentials: AuthCredentials) async throws -> [RunSummary]
    func fetchRunDetail(withId runId: String, credentials: AuthCredentials) async throws -> RunDetail
    func assignUser(to runId: String, userId: String, role: String, credentials: AuthCredentials) async throws
    func fetchCompanyUsers(credentials: AuthCredentials) async throws -> [CompanyUser]
    func updatePickItemStatus(runId: String, pickId: String, status: String, credentials: AuthCredentials) async throws
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

typealias RunParticipant = RunSummary.Participant

struct RunDetail: Equatable {
    struct Location: Identifiable, Equatable {
        let id: String
        let name: String?
        let address: String?
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

    struct Sku: Equatable {
        let id: String
        let code: String
        let name: String
        let type: String
        let isCheeseAndCrackers: Bool
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
        let status: String
        let pickedAt: Date?
        let coilItem: CoilItem
        let sku: Sku?
        let machine: Machine?
        let location: Location?

        var isPicked: Bool {
            status == "PICKED"
        }
    }

    struct ChocolateBox: Identifiable, Equatable {
        let id: String
        let number: Int
        let machine: Machine?
    }

    let id: String
    let status: String
    let companyId: String
    let scheduledFor: Date?
    let pickingStartedAt: Date?
    let pickingEndedAt: Date?
    let createdAt: Date
    let picker: RunParticipant?
    let runner: RunParticipant?
    let locations: [Location]
    let machines: [Machine]
    let pickItems: [PickItem]
    let chocolateBoxes: [ChocolateBox]

    var runDate: Date {
        scheduledFor ?? createdAt
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
                throw RunsServiceError.runNotFound
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
    
    func updatePickItemStatus(runId: String, pickId: String, status: String, credentials: AuthCredentials) async throws {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("runs")
        url.appendPathComponent(runId)
        url.appendPathComponent("picks")
        url.appendPathComponent(pickId)

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
            if httpResponse.statusCode == 404 {
                throw RunsServiceError.runNotFound
            }
            throw RunsServiceError.serverError(code: httpResponse.statusCode)
        }
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

        func toLocation() -> RunDetail.Location {
            RunDetail.Location(id: id, name: name, address: address)
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
        let isCheeseAndCrackers: Bool

        func toSku() -> RunDetail.Sku {
            RunDetail.Sku(id: id, code: code, name: name, type: type, isCheeseAndCrackers: isCheeseAndCrackers)
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
        let status: String
        let pickedAt: Date?
        let coilItem: CoilItem
        let coil: Coil
        let sku: Sku?
        let machine: Machine?
        let location: Location?

        func toPickItem() -> RunDetail.PickItem {
            let coilDomain = coil.toCoil()
            return RunDetail.PickItem(
                id: id,
                count: count,
                status: status,
                pickedAt: pickedAt,
                coilItem: coilItem.toCoilItem(with: coilDomain),
                sku: sku?.toSku(),
                machine: machine?.toMachine(),
                location: location?.toLocation()
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

    let id: String
    let status: String
    let companyId: String
    let scheduledFor: Date?
    let pickingStartedAt: Date?
    let pickingEndedAt: Date?
    let createdAt: Date
    let picker: Participant?
    let runner: Participant?
    let locations: [Location]
    let machines: [Machine]
    let pickItems: [PickItem]
    let chocolateBoxes: [ChocolateBox]

    func toDetail() -> RunDetail {
        RunDetail(
            id: id,
            status: status,
            companyId: companyId,
            scheduledFor: scheduledFor,
            pickingStartedAt: pickingStartedAt,
            pickingEndedAt: pickingEndedAt,
            createdAt: createdAt,
            picker: picker?.toParticipant(),
            runner: runner?.toParticipant(),
            locations: locations.map { $0.toLocation() },
            machines: machines.map { $0.toMachine() },
            pickItems: pickItems.filter { $0.count > 0 }.map { $0.toPickItem() },
            chocolateBoxes: chocolateBoxes.map { $0.toChocolateBox() }
        )
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
    case insufficientPermissions
    case roleAlreadyAssigned

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't connect to RunDaddy right now. Please try again."
        case let .serverError(code):
            return "Fetching runs failed with an unexpected error (code \(code))."
        case .runNotFound:
            return "We couldn't find details for that run. It may have been removed."
        case .insufficientPermissions:
            return "You don't have permission to assign this role."
        case .roleAlreadyAssigned:
            return "This role is already assigned to another user."
        }
    }
}
