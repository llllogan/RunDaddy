//
//  AnalyticsService.swift
//  PickAgent
//
//  Created by ChatGPT on 5/24/2025.
//

import Foundation

protocol AnalyticsServicing {
    func fetchDailyInsights(lookbackDays: Int?, credentials: AuthCredentials) async throws -> DailyInsights
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

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
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
