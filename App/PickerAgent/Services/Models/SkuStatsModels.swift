import Foundation

enum SkuPeriod: String, CaseIterable, Identifiable, Codable {
    case week
    case month
    case quarter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .week:
            return "Week"
        case .month:
            return "Month"
        case .quarter:
            return "Quarter"
        }
    }

    var dayCount: Int {
        switch self {
        case .week:
            return 7
        case .month:
            return 30
        case .quarter:
            return 90
        }
    }
}

struct SkuStatsResponse: Codable {
    let generatedAt: String
    let timeZone: String
    let period: SkuPeriod
    let rangeStart: String
    let rangeEnd: String
    let lookbackDays: Int
    let progress: SkuStatsProgress
    let percentageChange: SkuPercentageChange?
    let bestMachine: SkuBestMachine?
    let points: [SkuStatsPoint]
    let mostRecentPick: MostRecentPick?
}

struct SkuStatsProgress: Codable {
    let elapsedSeconds: Double
    let periodSeconds: Double
    let ratio: Double
}

struct SkuStatsPoint: Codable, Identifiable {
    let date: String
    let totalItems: Int
    let machines: [SkuStatsMachineBreakdown]

    var id: String { date }
}

struct SkuStatsMachineBreakdown: Codable, Identifiable {
    let machineId: String
    let machineCode: String
    let machineName: String?
    let count: Int

    var id: String { machineId }
}

struct SkuBestMachine: Codable, Identifiable {
    let machineId: String
    let machineCode: String
    let machineName: String?
    let totalPacks: Int

    var id: String { machineId }
}

struct SkuPercentageChange: Codable {
    let value: Double
    let trend: String // "up", "down", "neutral"
}

struct MostRecentPick: Codable {
    let pickedAt: String
    let locationName: String
    let runId: String
}
