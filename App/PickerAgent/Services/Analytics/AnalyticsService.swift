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
    func fetchDashboardMomentum(credentials: AuthCredentials) async throws -> DashboardMomentumSnapshot
    func fetchMachinePickTotals(
        lookbackDays: Int,
        credentials: AuthCredentials
    ) async throws -> [DashboardMomentumSnapshot.MachineSlice]
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
    let rangeStart: String
    let rangeEnd: String
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
    let rangeStart: String
    let rangeEnd: String
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
    let rangeStart: String
    let rangeEnd: String
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

struct DashboardMomentumSnapshot: Equatable {
    struct MachineSlice: Equatable, Identifiable {
        let machineId: String
        let name: String
        let totalPicks: Int

        var id: String { machineId }

        var displayName: String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Machine" : trimmed
        }
    }

    struct MachineTouchPoint: Equatable, Identifiable {
        let weekStart: Date
        let weekEnd: Date
        let totalMachines: Int

        var id: Date { weekStart }

        var weekLabel: String {
            weekStart.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    struct AnalyticsSummary: Equatable {
        struct SkuComparison: Equatable {
            struct Totals: Equatable {
                let currentWeek: Int
                let previousWeek: Int

                var maxTotal: Int {
                    max(currentWeek, previousWeek)
                }
            }

            struct Segment: Equatable, Identifiable {
                let skuId: String
                let currentTotal: Int
                let previousTotal: Int

                var id: String {
                    skuId.isEmpty ? "segment-unknown" : skuId
                }
            }

            let totals: Totals
            let segments: [Segment]

            var hasData: Bool {
                totals.currentWeek > 0 || totals.previousWeek > 0
            }
        }

        let skuComparison: SkuComparison?

        static var empty: AnalyticsSummary {
            AnalyticsSummary(skuComparison: nil)
        }
    }

    let generatedAt: Date
    let timeZone: String
    let machinePickTotals: [MachineSlice]
    let machineTouches: [MachineTouchPoint]
    let analytics: AnalyticsSummary
}

enum AnalyticsServiceError: LocalizedError {
    case invalidResponse
    case serverError(code: Int)
    case unableToDecode
    case noCompanyAccess
    case missingCredentials

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
        case .missingCredentials:
            return "We couldn't find your credentials. Please sign in again."
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

    func fetchDashboardMomentum(credentials: AuthCredentials) async throws -> DashboardMomentumSnapshot {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("analytics")
        url.appendPathComponent("dashboard")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "timezone", value: TimeZone.current.identifier)]
        let resolvedURL = components?.url ?? url

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        async let machineSlices = fetchMachinePickTotals(lookbackDays: 14, credentials: credentials)
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
            let payload = try decoder.decode(DashboardMomentumResponse.self, from: data)
            let machines = (try? await machineSlices) ?? []
            return payload.toDomain(machineSlices: machines)
        } catch {
            throw AnalyticsServiceError.unableToDecode
        }
    }

    func fetchMachinePickTotals(
        lookbackDays: Int,
        credentials: AuthCredentials
    ) async throws -> [DashboardMomentumSnapshot.MachineSlice] {
        var url = AppConfig.apiBaseURL
        url.appendPathComponent("analytics")
        url.appendPathComponent("machines")
        url.appendPathComponent("pick-totals")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "timezone", value: TimeZone.current.identifier),
            URLQueryItem(name: "lookbackDays", value: String(lookbackDays))
        ]
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
            let payload = try decoder.decode(MachinePickTotalsResponse.self, from: data)
            return payload.machines.map { machine in
                DashboardMomentumSnapshot.MachineSlice(
                    machineId: machine.machineId,
                    name: machine.displayName,
                    totalPicks: machine.totalItems
                )
            }
        } catch {
            throw AnalyticsServiceError.unableToDecode
        }
    }

}

private enum AnalyticsDateParser {
    static func date(from value: String, timeZoneIdentifier: String) -> Date {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return Date()
        }

        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = timeZone

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0

        return calendar.date(from: components) ?? Date()
    }
}

private struct DailyInsightsResponse: Decodable {
    struct Point: Decodable {
        let date: String
        let start: String
        let end: String
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
            start = try container.decode(String.self, forKey: .start)
            end = try container.decode(String.self, forKey: .end)

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
    let rangeStart: String
    let rangeEnd: String
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
                    start: AnalyticsDateParser.date(from: point.start, timeZoneIdentifier: timeZone),
                    end: AnalyticsDateParser.date(from: point.end, timeZoneIdentifier: timeZone),
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
    let rangeStart: String
    let rangeEnd: String
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
        let start: String
        let end: String
        let comparisonEnd: String
        let totalItems: Int

        private enum CodingKeys: String, CodingKey {
            case start
            case end
            case comparisonEnd
            case totalItems
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            start = try container.decode(String.self, forKey: .start)
            end = try container.decode(String.self, forKey: .end)
            comparisonEnd = try container.decode(String.self, forKey: .comparisonEnd)

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
        let start: String
        let end: String
        let comparisonEnd: String
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
            start = try container.decode(String.self, forKey: .start)
            end = try container.decode(String.self, forKey: .end)
            comparisonEnd = try container.decode(String.self, forKey: .comparisonEnd)

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
                        start: AnalyticsDateParser.date(from: period.currentPeriod.start, timeZoneIdentifier: timeZone),
                        end: AnalyticsDateParser.date(from: period.currentPeriod.end, timeZoneIdentifier: timeZone),
                        comparisonEnd: AnalyticsDateParser.date(from: period.currentPeriod.comparisonEnd, timeZoneIdentifier: timeZone),
                        totalItems: period.currentPeriod.totalItems
                    ),
                    previousPeriods: period.previousPeriods.map { historical in
                        PackPeriodComparisons.HistoricalPeriod(
                            index: historical.index,
                            start: AnalyticsDateParser.date(from: historical.start, timeZoneIdentifier: timeZone),
                            end: AnalyticsDateParser.date(from: historical.end, timeZoneIdentifier: timeZone),
                            comparisonEnd: AnalyticsDateParser.date(from: historical.comparisonEnd, timeZoneIdentifier: timeZone),
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
    let rangeStart: String
    let rangeEnd: String
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

private struct MachinePickTotalsResponse: Decodable {
    struct Machine: Decodable {
        let machineId: String
        let machineCode: String
        let machineDescription: String
        let totalItems: Int

        private enum CodingKeys: String, CodingKey {
            case machineId
            case machineCode
            case machineDescription
            case totalItems
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            machineId = try container.decode(String.self, forKey: .machineId)
            machineCode = try container.decode(String.self, forKey: .machineCode)
            machineDescription = try container.decode(String.self, forKey: .machineDescription)

            if let value = try? container.decode(Int.self, forKey: .totalItems) {
                totalItems = max(value, 0)
            } else if let doubleValue = try? container.decode(Double.self, forKey: .totalItems) {
                totalItems = max(Int(doubleValue.rounded()), 0)
            } else {
                totalItems = 0
            }
        }

        var displayName: String {
            let trimmed = machineDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
            let trimmedCode = machineCode.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCode.isEmpty ? "Machine" : trimmedCode
        }
    }

    let machines: [Machine]
}

private struct DashboardMomentumResponse: Decodable {
    struct MachineTouchPoint: Decodable {
        let weekStart: String
        let weekEnd: String
        let totalMachines: Int

        private enum CodingKeys: String, CodingKey {
            case weekStart
            case weekEnd
            case totalMachines
        }

        func toDomain(timeZone: String) -> DashboardMomentumSnapshot.MachineTouchPoint {
            DashboardMomentumSnapshot.MachineTouchPoint(
                weekStart: AnalyticsDateParser.date(from: weekStart, timeZoneIdentifier: timeZone),
                weekEnd: AnalyticsDateParser.date(from: weekEnd, timeZoneIdentifier: timeZone),
                totalMachines: max(totalMachines, 0)
            )
        }
    }

    struct AnalyticsSummary: Decodable {
        struct SkuComparison: Decodable {
            struct Segment: Decodable {
                let skuId: String
                let currentTotal: Int
                let previousTotal: Int

                private enum CodingKeys: String, CodingKey {
                    case skuId
                    case currentTotal
                    case previousTotal
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    skuId = try container.decode(String.self, forKey: .skuId)
                    currentTotal = DashboardMomentumResponse.decodeCount(from: container, key: .currentTotal)
                    previousTotal = DashboardMomentumResponse.decodeCount(from: container, key: .previousTotal)
                }

                func toDomain() -> DashboardMomentumSnapshot.AnalyticsSummary.SkuComparison.Segment {
                    DashboardMomentumSnapshot.AnalyticsSummary.SkuComparison.Segment(
                        skuId: skuId,
                        currentTotal: currentTotal,
                        previousTotal: previousTotal
                    )
                }
            }

            struct Totals: Decodable {
                let currentWeek: Int
                let previousWeek: Int
            }

            let totals: Totals
            let segments: [Segment]

            func toDomain() -> DashboardMomentumSnapshot.AnalyticsSummary.SkuComparison {
                DashboardMomentumSnapshot.AnalyticsSummary.SkuComparison(
                    totals: DashboardMomentumSnapshot.AnalyticsSummary.SkuComparison.Totals(
                        currentWeek: max(totals.currentWeek, 0),
                        previousWeek: max(totals.previousWeek, 0)
                    ),
                    segments: segments.map { $0.toDomain() }
                )
            }
        }

        let skuComparison: SkuComparison?

        func toDomain() -> DashboardMomentumSnapshot.AnalyticsSummary {
            DashboardMomentumSnapshot.AnalyticsSummary(
                skuComparison: skuComparison?.toDomain()
            )
        }
    }

    let generatedAt: Date
    let timeZone: String
    let analytics: AnalyticsSummary?
    let machineTouches: [MachineTouchPoint]?

    func toDomain(machineSlices: [DashboardMomentumSnapshot.MachineSlice]) -> DashboardMomentumSnapshot {
        let touches = machineTouches?.map { $0.toDomain(timeZone: timeZone) } ?? []
        return DashboardMomentumSnapshot(
            generatedAt: generatedAt,
            timeZone: timeZone,
            machinePickTotals: machineSlices,
            machineTouches: touches,
            analytics: analytics?.toDomain() ?? .empty
        )
    }

    private static func decodeCount<KeyType: CodingKey>(
        from container: KeyedDecodingContainer<KeyType>,
        key: KeyType
    ) -> Int {
        if let value = try? container.decode(Int.self, forKey: key) {
            return max(value, 0)
        }
        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            return max(Int(doubleValue.rounded()), 0)
        }
        return 0
    }
}
