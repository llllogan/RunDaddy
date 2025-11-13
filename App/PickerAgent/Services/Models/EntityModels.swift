import Foundation

struct Machine: Codable, Identifiable {
    let id: String
    let code: String
    let description: String?
    let machineType: MachineType?
    let location: Location?
}

struct MachineType: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
}

struct Location: Codable, Identifiable {
    let id: String
    let name: String
    let address: String?
}

struct SKU: Codable, Identifiable {
    let id: String
    let code: String
    let name: String
    let type: String
    let category: String?
    let countNeededPointer: String?
    let isCheeseAndCrackers: Bool
}