import Foundation

struct SkuStatsResponse: Codable {
    let generatedAt: String
    let timeZone: String
    let mostRecentPick: MostRecentPick?
    let percentageChanges: SkuPercentageChanges
    let periods: SkuStatsPeriods
}

struct SkuStatsPeriods: Codable {
    let week: [SkuDayStat]
    let month: [SkuDayStat]
    let quarter: [SkuDayStat]
}

struct SkuPercentageChanges: Codable {
    let week: SkuPercentageChange?
    let month: SkuPercentageChange?
    let quarter: SkuPercentageChange?
}

struct SkuPercentageChange: Codable {
    let value: Double
    let trend: String // "up", "down", "neutral"
}

struct SkuDayStat: Codable, Identifiable {
    let date: String
    let total: Int
    let locations: [SkuLocationStat]
    
    var id: String { date }
}

struct SkuLocationStat: Codable, Identifiable {
    let name: String
    let count: Int
    
    var id: String { name }
}

struct MostRecentPick: Codable {
    let pickedAt: String
    let locationName: String
    let runId: String
}