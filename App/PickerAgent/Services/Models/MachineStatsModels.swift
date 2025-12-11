import Foundation

struct MachineStatsResponse: Codable {
    let generatedAt: String
    let timeZone: String
    let period: SkuPeriod
    let rangeStart: String
    let rangeEnd: String
    let lookbackDays: Int
    let progress: MachineStatsProgress
    let percentageChange: SkuPercentageChange?
    let bestSku: MachineBestSku?
    let lastStocked: MachineLastStocked?
    let firstSeen: String?
    let points: [MachineStatsPoint]
}

struct MachineStatsProgress: Codable {
    let elapsedSeconds: Double
    let periodSeconds: Double
    let ratio: Double
}

struct MachineStatsPoint: Codable, Identifiable {
    let date: String
    let totalItems: Int
    let skus: [MachineStatsSkuBreakdown]

    var id: String { date }
}

struct MachineStatsSkuBreakdown: Codable, Identifiable {
    let skuId: String
    let skuCode: String
    let skuName: String
    let count: Int

    var id: String { skuId }
}

struct MachineBestSku: Codable, Identifiable {
    let skuId: String
    let skuCode: String
    let skuName: String
    let skuType: String
    let totalPacks: Int

    var id: String { skuId }
}

struct MachineLastStocked: Codable {
    let stockedAt: String
    let runId: String
}
