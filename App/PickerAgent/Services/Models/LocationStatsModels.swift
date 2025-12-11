import Foundation

struct LocationStatsResponse: Codable {
    let generatedAt: String
    let timeZone: String
    let period: SkuPeriod
    let rangeStart: String
    let rangeEnd: String
    let lookbackDays: Int
    let progress: LocationStatsProgress
    let percentageChange: SkuPercentageChange?
    let lastPacked: LocationLastPacked?
    let firstSeen: String?
    let bestMachine: LocationBestMachine?
    let bestSku: LocationBestSku?
    let machineSalesShare: [LocationMachineSalesShare]?
    let points: [LocationStatsPoint]
}

struct LocationStatsProgress: Codable {
    let elapsedSeconds: Double
    let periodSeconds: Double
    let ratio: Double
}

struct LocationStatsPoint: Codable, Identifiable {
    let date: String
    let totalItems: Int
    let machines: [LocationStatsMachineBreakdown]
    let skus: [LocationStatsSkuBreakdown]

    var id: String { date }
}

struct LocationStatsMachineBreakdown: Codable, Identifiable {
    let machineId: String
    let machineCode: String
    let machineName: String?
    let count: Int

    var id: String { machineId }

    var displayName: String {
        guard let machineName = machineName?.trimmingCharacters(in: .whitespacesAndNewlines), !machineName.isEmpty else {
            let trimmedCode = machineCode.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCode.isEmpty ? "Machine" : trimmedCode
        }
        return machineName
    }
}

struct LocationMachineSalesShare: Codable, Identifiable {
    let machineId: String
    let machineCode: String
    let machineName: String?
    let count: Int
    let percentage: Double

    var id: String { machineId }

    var displayName: String {
        let trimmed = machineName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        let codeTrimmed = machineCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return codeTrimmed.isEmpty ? "Machine" : codeTrimmed
    }

    var roundedPercentageText: String {
        if percentage == 0 {
            return "0% of sales"
        }
        let rounded = percentage.rounded(.toNearestOrAwayFromZero)
        if abs(rounded - percentage) < 0.05 {
            return "\(Int(rounded))% of sales"
        }
        return String(format: "%.1f%% of sales", percentage)
    }
}

struct LocationStatsSkuBreakdown: Codable, Identifiable {
    let skuId: String
    let skuCode: String
    let skuName: String
    let count: Int

    var id: String { skuId }

    var displayName: String {
        let trimmed = skuName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? skuCode : trimmed
    }
}

struct LocationBestMachine: Codable, Identifiable {
    let machineId: String
    let machineCode: String
    let machineName: String?
    let totalPacks: Int

    var id: String { machineId }

    var displayName: String {
        let trimmed = machineName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? machineCode : trimmed
    }
}

struct LocationBestSku: Codable, Identifiable {
    let skuId: String
    let skuCode: String
    let skuName: String
    let skuType: String
    let totalPacks: Int

    var id: String { skuId }

    var displayName: String {
        let trimmed = skuName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? skuCode : trimmed
        let typeTrimmed = skuType.trimmingCharacters(in: .whitespacesAndNewlines)
        if typeTrimmed.isEmpty || typeTrimmed.caseInsensitiveCompare("General") == .orderedSame {
            return base
        }
        return "\(base) (\(typeTrimmed))"
    }
}

struct LocationLastPacked: Codable {
    let pickedAt: String
    let runId: String
    let machineId: String?
    let machineCode: String?
    let machineName: String?

    var machineDisplayName: String? {
        let trimmed = machineName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        guard let machineCode else { return nil }
        let codeTrimmed = machineCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return codeTrimmed.isEmpty ? nil : codeTrimmed
    }
}
