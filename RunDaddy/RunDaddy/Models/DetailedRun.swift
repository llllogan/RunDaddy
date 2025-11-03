//
//  DetailedRun.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import Foundation

struct APIDetailedRun: Codable, Identifiable {
    let id: String
    let companyId: String
    let status: String
    let scheduledFor: Date?
    let pickingStartedAt: Date?
    let pickingEndedAt: Date?
    let createdAt: Date
    let pickerId: String?
    let runnerId: String?
    let picker: APIUser?
    let runner: APIUser?
    let pickEntries: [APIPickEntry]
    let chocolateBoxes: [APIChocolateBox]

    var pickerFullName: String? {
        picker?.fullName
    }

    var runnerFullName: String? {
        runner?.fullName
    }
}

struct APIUser: Codable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let phone: String?

    var fullName: String {
        "\(firstName) \(lastName)"
    }
}

struct APIPickEntry: Codable, Identifiable {
    let id: String
    let runId: String
    let coilItemId: String
    let count: Int
    let status: String
    let pickedAt: Date?
    let coilItem: APICoilItem
}

struct APICoilItem: Codable, Identifiable {
    let id: String
    let coilId: String
    let skuId: String
    let par: Int
    let sku: APISKU
    let coil: APICoil
}

struct APISKU: Codable, Identifiable {
    let id: String
    let code: String
    let name: String
    let type: String?
    let isCheeseAndCrackers: Bool?
}

struct APICoil: Codable, Identifiable {
    let id: String
    let machineId: String
    let code: String
    let machine: APIMachine
}

struct APIMachine: Codable, Identifiable {
    let id: String
    let companyId: String
    let code: String
    let description: String?
    let machineTypeId: String
    let locationId: String?
    let machineType: APIMachineType
    let location: APILocation?

    var machinePointer: String {
        "\(code)"
    }
}

struct APIMachineType: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
}

struct APILocation: Codable, Identifiable {
    let id: String
    let companyId: String
    let name: String
    let address: String?
}

struct APIChocolateBox: Codable, Identifiable {
    let id: String
    let runId: String
    let machineId: String
    let number: Int
    let machine: APIMachine
}