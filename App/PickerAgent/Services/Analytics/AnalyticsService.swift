//
//  AnalyticsService.swift
//  PickAgent
//
//  Created by ChatGPT on 5/24/2025.
//

import Foundation

protocol AnalyticsServicing {
    func fetchDailyInsights(lookbackDays: Int?, credentials: AuthCredentials) async throws -> DailyInsights
    func fetchTopLocations(lookbackDays: Int?, credentials: AuthCredentials) async throws -> TopLocations
    func fetchPackPeriodComparisons(credentials: AuthCredentials) async throws -> PackPeriodComparisons
    func fetchTopSkus(
        lookbackDays: Int?,
        locationId: String?,
        machineId: String?,
        credentials: AuthCredentials
    ) async throws -> TopSkuStats
}

struct DailyInsights: Equatable {
    struct Point: Identifiable, Equatable {
        var id: Date { start }
        let label: String
        let start: Date
        let end: Date
        let totalItems: Int
        let itemsPacked: Int
    }

    let generatedAt: Date
    let timeZone: String
    let lookbackDays: Int
    let rangeStart: Date
    let rangeEnd: Date
    let points: [Point]

    var totalItems: Int {
        points.reduce(0) { $0 + $1.totalItems }
    }

    var averagePerDay: Double {
        guard !points.isEmpty else { return 0 }
        return Double(totalItems) / Double(points.count)
    }
}

struct TopLocations: Equatable {
    struct Location: Identifiable, Equatable {
        var id: String { locationId }
        let locationId: String
        let locationName: String
        let totalItems: Int
        let machines: [Machine]
    }

    struct Machine: Identifiable, Equatable {
        var id: String { machineId }
        let machineId: String
        let machineCode: String
        let machineDescription: String
        let totalItems: Int
        
        var displayName: String {
            let trimmed = machineDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? machineCode : trimmed
        }
    }

    let generatedAt: Date
    let timeZone: String
    let lookbackDays: Int
    let rangeStart: Date
    let rangeEnd: Date
    let locations: [Location]

    var totalItems: Int {
        locations.reduce(0) { $0 + $1.totalItems }
    }
}

struct TopSkuStats: Equatable {
    struct Sku: Identifiable, Equatable {
        let skuId: String
        let skuCode: String
        let skuName: String
        let skuType: String
        let totalPicked: Int

        var id: String { skuId }

        var displayLabel: String {
            let trimmedName = skuName.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseName = trimmedName.isEmpty ? skuCode : trimmedName
            let trimmedType = skuType.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedType.caseInsensitiveCompare("General") == .orderedSame || trimmedType.isEmpty {
                return baseName
            }
            return "\(baseName) (\(trimmedType))"
        }
    }

    struct LocationOption: Identifiable, Equatable {
        let locationId: String
        let name: String
        let totalItems: Int

        var id: String { locationId }

        var displayName: String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Location" : trimmed
        }
    }

    struct MachineOption: Identifiable, Equatable {
        let machineId: String
        let code: String
        let description: String
        let locationId: String?
        let locationName: String?
        let totalItems: Int

        var id: String { machineId }

        var displayName: String {
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
            let codeTrimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            return codeTrimmed.isEmpty ? "Machine" : codeTrimmed
        }
    }

    let generatedAt: Date
    let timeZone: String
    let lookbackDays: Int
    let rangeStart: Date
    let rangeEnd: Date
    let limit: Int
    let appliedLocationId: String?
    let appliedMachineId: String?
    let skus: [Sku]
    let locations: [LocationOption]
    let machines: [MachineOption]

    var totalPicked: Int {
        skus.reduce(0) { $0 + $1.totalPicked }
    }

    var isEmpty: Bool {
        skus.isEmpty
    }
}

struct PackPeriodComparisons: Equatable {
    struct PeriodComparison: Identifiable, Equatable {
        let period: PeriodKind
        let progressPercentage: Double
        let comparisonDurationMs: Double
        let currentPeriod: PeriodSnapshot
        let previousPeriods: [HistoricalPeriod]
        let averages: Averages

        var id: PeriodKind { period }
        var progressFraction: Double {
            max(0, min(progressPercentage / 100.0, 1.0))
        }
    }

    struct PeriodSnapshot: Equatable {
        let start: Date
        let end: Date
        let comparisonEnd: Date
        let totalItems: Int
    }

    struct HistoricalPeriod: Identifiable, Equatable {
        let index: Int
        let start: Date
        let end: Date
        let comparisonEnd: Date
        let totalItems: Int

        var id: Int { index }
    }

    struct Averages: Equatable {
        let previousAverage: Double?
        let deltaFromPreviousAverage: Double?
        let deltaPercentage: Double?
    }

    enum PeriodKind: String, Codable, CaseIterable, Equatable, Identifiable {
        case week
        case month
        case quarter

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .week: return "Week"
            case .month: return "Month"
            case .quarter: return "Quarter"
            }
        }
    }

    let generatedAt: Date
    let timeZone: String
    let periods: [PeriodComparison]

    var isEmpty: Bool {
        periods.isEmpty
    }
}

enum AnalyticsServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case unableToDecode
    case noCompanyAccess

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't reach the analytics service. Please try again."
        case let .serverError(code):
            return "Analytics temporarily unavailable (code: \(code))."
        case .unableToDecode:
            return "Received analytics data in an unexpected format."
        case .noCompanyAccess:
            return "Join or select a company to unlock insights."
        }
    }
}

final class AnalyticsService: AnalyticsServicing {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(urlSession: URLSession? = nil) {
        self.urlSession = urlSession ?? URLSession.shared
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchDailyInsights(lookbackDays: Int?, credentials: AuthCredentials) async throws -> DailyInsights {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("analytics")
        url.appendPathComponent("daily-totals")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "timezone", value: TimeZone.current.identifier)]
        if let lookbackDays, lookbackDays > 0 {
            queryItems.append(URLQueryItem(name: "lookbackDays", value: String(lookbackDays)))
        }
        components?.queryItems = queryItems
        let resolvedURL = components?.url ?? url

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalyticsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw AnalyticsServiceError.noCompanyAccess
            }
            throw AnalyticsServiceError.serverError(code: httpResponse.statusCode)
        }

        do {
            let payload = try decoder.decode(DailyInsightsResponse.self, from: data)
            return payload.toDomain()
        } catch {
            throw AnalyticsServiceError.unableToDecode
        }
    }

    func fetchTopLocations(lookbackDays: Int?, credentials: AuthCredentials) async throws -> TopLocations {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("analytics")
        url.appendPathComponent("locations")
        url.appendPathComponent("top")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "timezone", value: TimeZone.current.identifier)]
        if let lookbackDays, lookbackDays > 0 {
            queryItems.append(URLQueryItem(name: "lookbackDays", value: String(lookbackDays)))
        }
        components?.queryItems = queryItems
        let resolvedURL = components?.url ?? url

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalyticsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw AnalyticsServiceError.noCompanyAccess
            }
            throw AnalyticsServiceError.serverError(code: httpResponse.statusCode)
        }

        do {
            let payload = try decoder.decode(TopLocationsResponse.self, from: data)
            return payload.toDomain()
        } catch {
            throw AnalyticsServiceError.unableToDecode
        }
    }

    func fetchPackPeriodComparisons(credentials: AuthCredentials) async throws -> PackPeriodComparisons {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("analytics")
        url.appendPathComponent("packs")
        url.appendPathComponent("period-comparison")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = [URLQueryItem(name: "timezone", value: TimeZone.current.identifier)]
        components?.queryItems = queryItems
        let resolvedURL = components?.url ?? url

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalyticsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw AnalyticsServiceError.noCompanyAccess
            }
            throw AnalyticsServiceError.serverError(code: httpResponse.statusCode)
        }

        do {
            let payload = try decoder.decode(PackPeriodComparisonsResponse.self, from: data)
            return payload.toDomain()
        } catch {
            throw AnalyticsServiceError.unableToDecode
        }
    }

    func fetchTopSkus(
        lookbackDays: Int?,
        locationId: String?,
        machineId: String?,
        credentials: AuthCredentials
    ) async throws -> TopSkuStats {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("analytics")
        url.appendPathComponent("skus")
        url.appendPathComponent("top-picked")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "timezone", value: TimeZone.current.identifier)]
        if let lookbackDays, lookbackDays > 0 {
            queryItems.append(URLQueryItem(name: "lookbackDays", value: String(lookbackDays)))
        }
        if let locationId, !locationId.isEmpty {
            queryItems.append(URLQueryItem(name: "locationId", value: locationId))
        }
        if let machineId, !machineId.isEmpty {
            queryItems.append(URLQueryItem(name: "machineId", value: machineId))
        }
        components?.queryItems = queryItems
        let resolvedURL = components?.url ?? url

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalyticsServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw AnalyticsServiceError.noCompanyAccess
            }
            throw AnalyticsServiceError.serverError(code: httpResponse.statusCode)
        }

        do {
            let payload = try decoder.decode(TopSkuStatsResponse.self, from: data)
            return payload.toDomain()
        } catch {
            throw AnalyticsServiceError.unableToDecode
        }
    }
}

private struct DailyInsightsResponse: Decodable {
    struct Point: Decodable {
        let date: String
        let start: Date
        let end: Date
        let totalItems: Int
        let itemsPacked: Int

        private enum CodingKeys: String, CodingKey {
            case date
            case start
            case end
            case totalItems
            case itemsPacked
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(String.self, forKey: .date)
            start = try container.decode(Date.self, forKey: .start)
            end = try container.decode(Date.self, forKey: .end)

            if let intValue = try? container.decode(Int.self, forKey: .totalItems) {
                totalItems = intValue
            } else if let doubleValue = try? container.decode(Double.self, forKey: .totalItems) {
                totalItems = Int(doubleValue.rounded())
            } else {
                totalItems = 0
            }

            if let intValue = try? container.decode(Int.self, forKey: .itemsPacked) {
                itemsPacked = intValue
            } else if let doubleValue = try? container.decode(Double.self, forKey: .itemsPacked) {
                itemsPacked = Int(doubleValue.rounded())
            } else {
                itemsPacked = 0
            }
        }
    }

    let generatedAt: Date
    let timeZone: String
    let lookbackDays: Int
    let rangeStart: Date
    let rangeEnd: Date
    let points: [Point]

    func toDomain() -> DailyInsights {
        DailyInsights(
            generatedAt: generatedAt,
            timeZone: timeZone,
            lookbackDays: lookbackDays,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            points: points.map { point in
                DailyInsights.Point(
                    label: point.date,
                    start: point.start,
                    end: point.end,
                    totalItems: max(point.totalItems, 0),
                    itemsPacked: max(point.itemsPacked, 0)
                )
            }
        )
    }
}

private struct TopLocationsResponse: Decodable {
    struct Location: Decodable {
        let locationId: String
        let locationName: String
        let totalItems: Int
        let machines: [Machine]
    }

    struct Machine: Decodable {
        let machineId: String
        let machineCode: String
        let machineDescription: String?
        let totalItems: Int
    }

    let generatedAt: Date
    let timeZone: String
    let lookbackDays: Int
    let rangeStart: Date
    let rangeEnd: Date
    let locations: [Location]

    func toDomain() -> TopLocations {
        TopLocations(
            generatedAt: generatedAt,
            timeZone: timeZone,
            lookbackDays: lookbackDays,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            locations: locations.map { location in
                TopLocations.Location(
                    locationId: location.locationId,
                    locationName: location.locationName,
                    totalItems: max(location.totalItems, 0),
                    machines: location.machines.map { machine in
                        TopLocations.Machine(
                            machineId: machine.machineId,
                            machineCode: machine.machineCode,
                            machineDescription: machine.machineDescription ?? "",
                            totalItems: max(machine.totalItems, 0)
                        )
                    }
                )
            }
        )
    }
}

private struct PackPeriodComparisonsResponse: Decodable {
    struct PeriodComparison: Decodable {
        let period: PackPeriodComparisons.PeriodKind
        let progressPercentage: Double
        let comparisonDurationMs: Double
        let currentPeriod: Snapshot
        let previousPeriods: [HistoricalSnapshot]
        let averages: Averages
    }

    struct Snapshot: Decodable {
        let start: Date
        let end: Date
        let comparisonEnd: Date
        let totalItems: Int

        private enum CodingKeys: String, CodingKey {
            case start
            case end
            case comparisonEnd
            case totalItems
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            start = try container.decode(Date.self, forKey: .start)
            end = try container.decode(Date.self, forKey: .end)
            comparisonEnd = try container.decode(Date.self, forKey: .comparisonEnd)

            if let intValue = try? container.decode(Int.self, forKey: .totalItems) {
                totalItems = max(intValue, 0)
            } else if let doubleValue = try? container.decode(Double.self, forKey: .totalItems) {
                totalItems = max(Int(doubleValue.rounded()), 0)
            } else {
                totalItems = 0
            }
        }
    }

    struct HistoricalSnapshot: Decodable {
        let index: Int
        let start: Date
        let end: Date
        let comparisonEnd: Date
        let totalItems: Int

        private enum CodingKeys: String, CodingKey {
            case index
            case start
            case end
            case comparisonEnd
            case totalItems
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            index = try container.decode(Int.self, forKey: .index)
            start = try container.decode(Date.self, forKey: .start)
            end = try container.decode(Date.self, forKey: .end)
            comparisonEnd = try container.decode(Date.self, forKey: .comparisonEnd)

            if let intValue = try? container.decode(Int.self, forKey: .totalItems) {
                totalItems = max(intValue, 0)
            } else if let doubleValue = try? container.decode(Double.self, forKey: .totalItems) {
                totalItems = max(Int(doubleValue.rounded()), 0)
            } else {
                totalItems = 0
            }
        }
    }

    struct Averages: Decodable {
        let previousAverage: Double?
        let deltaFromPreviousAverage: Double?
        let deltaPercentage: Double?
    }

    let generatedAt: Date
    let timeZone: String
    let periods: [PeriodComparison]

    func toDomain() -> PackPeriodComparisons {
        PackPeriodComparisons(
            generatedAt: generatedAt,
            timeZone: timeZone,
            periods: periods.map { period in
                PackPeriodComparisons.PeriodComparison(
                    period: period.period,
                    progressPercentage: period.progressPercentage,
                    comparisonDurationMs: period.comparisonDurationMs,
                    currentPeriod: PackPeriodComparisons.PeriodSnapshot(
                        start: period.currentPeriod.start,
                        end: period.currentPeriod.end,
                        comparisonEnd: period.currentPeriod.comparisonEnd,
                        totalItems: period.currentPeriod.totalItems
                    ),
                    previousPeriods: period.previousPeriods.map { historical in
                        PackPeriodComparisons.HistoricalPeriod(
                            index: historical.index,
                            start: historical.start,
                            end: historical.end,
                            comparisonEnd: historical.comparisonEnd,
                            totalItems: historical.totalItems
                        )
                    },
                    averages: PackPeriodComparisons.Averages(
                        previousAverage: period.averages.previousAverage,
                        deltaFromPreviousAverage: period.averages.deltaFromPreviousAverage,
                        deltaPercentage: period.averages.deltaPercentage
                    )
                )
            }
        )
    }
}

private struct TopSkuStatsResponse: Decodable {
    struct AppliedFilters: Decodable {
        let locationId: String?
        let machineId: String?
    }

    struct Sku: Decodable {
        let skuId: String
        let skuCode: String
        let skuName: String
        let skuType: String
        let totalPicked: Int

        private enum CodingKeys: String, CodingKey {
            case skuId
            case skuCode
            case skuName
            case skuType
            case totalPicked
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            skuId = try container.decode(String.self, forKey: .skuId)
            skuCode = try container.decode(String.self, forKey: .skuCode)
            skuName = try container.decode(String.self, forKey: .skuName)
            skuType = try container.decode(String.self, forKey: .skuType)

            if let intValue = try? container.decode(Int.self, forKey: .totalPicked) {
                totalPicked = max(intValue, 0)
            } else if let doubleValue = try? container.decode(Double.self, forKey: .totalPicked) {
                totalPicked = max(Int(doubleValue.rounded()), 0)
            } else {
                totalPicked = 0
            }
        }
    }

    struct Location: Decodable {
        let locationId: String
        let locationName: String
        let totalItems: Int

        private enum CodingKeys: String, CodingKey {
            case locationId
            case locationName
            case totalItems
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            locationId = try container.decode(String.self, forKey: .locationId)
            locationName = try container.decode(String.self, forKey: .locationName)
            if let value = try? container.decode(Int.self, forKey: .totalItems) {
                totalItems = max(value, 0)
            } else if let doubleValue = try? container.decode(Double.self, forKey: .totalItems) {
                totalItems = max(Int(doubleValue.rounded()), 0)
            } else {
                totalItems = 0
            }
        }
    }

    struct Machine: Decodable {
        let machineId: String
        let machineCode: String
        let machineDescription: String?
        let locationId: String?
        let locationName: String?
        let totalItems: Int

        private enum CodingKeys: String, CodingKey {
            case machineId
            case machineCode
            case machineDescription
            case locationId
            case locationName
            case totalItems
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            machineId = try container.decode(String.self, forKey: .machineId)
            machineCode = try container.decode(String.self, forKey: .machineCode)
            machineDescription = try container.decodeIfPresent(String.self, forKey: .machineDescription)
            locationId = try container.decodeIfPresent(String.self, forKey: .locationId)
            locationName = try container.decodeIfPresent(String.self, forKey: .locationName)

            if let value = try? container.decode(Int.self, forKey: .totalItems) {
                totalItems = max(value, 0)
            } else if let doubleValue = try? container.decode(Double.self, forKey: .totalItems) {
                totalItems = max(Int(doubleValue.rounded()), 0)
            } else {
                totalItems = 0
            }
        }
    }

    let generatedAt: Date
    let timeZone: String
    let lookbackDays: Int
    let rangeStart: Date
    let rangeEnd: Date
    let limit: Int
    let appliedFilters: AppliedFilters
    let skus: [Sku]
    let locations: [Location]
    let machines: [Machine]

    func toDomain() -> TopSkuStats {
        TopSkuStats(
            generatedAt: generatedAt,
            timeZone: timeZone,
            lookbackDays: lookbackDays,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            limit: limit,
            appliedLocationId: appliedFilters.locationId,
            appliedMachineId: appliedFilters.machineId,
            skus: skus.map { sku in
                TopSkuStats.Sku(
                    skuId: sku.skuId,
                    skuCode: sku.skuCode,
                    skuName: sku.skuName,
                    skuType: sku.skuType,
                    totalPicked: sku.totalPicked
                )
            },
            locations: locations.map { location in
                TopSkuStats.LocationOption(
                    locationId: location.locationId,
                    name: location.locationName,
                    totalItems: location.totalItems
                )
            },
            machines: machines.map { machine in
                TopSkuStats.MachineOption(
                    machineId: machine.machineId,
                    code: machine.machineCode,
                    description: machine.machineDescription ?? "",
                    locationId: machine.locationId,
                    locationName: machine.locationName,
                    totalItems: machine.totalItems
                )
            }
        )
    }
}
