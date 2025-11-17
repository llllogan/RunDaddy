//
//  PreviewRunsService.swift
//  PickAgent
//
//  Created by Logan Janssen on 11/5/2025.
//

import Foundation

struct PreviewRunsService: RunsServicing {
    func fetchRuns(for schedule: RunsSchedule, credentials: AuthCredentials) async throws -> [RunSummary] {
        []
    }
    
    func fetchAllRuns(credentials: AuthCredentials) async throws -> [RunSummary] {
        // Return some sample runs for testing
        return [
            .previewReady,
            .previewPicking,
            .previewPicked
        ].sorted { run1, run2 in
            let date1 = run1.scheduledFor ?? run1.createdAt
            let date2 = run2.scheduledFor ?? run2.createdAt
            return date1 > date2
        }
    }
    
    func fetchRunDetail(withId runId: String, credentials: AuthCredentials) async throws -> RunDetail {
        let downtown = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
        let uptown = RunDetail.Location(id: "loc-2", name: "Uptown Annex", address: "456 Oak Avenue")

        let snackType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
        let drinkType = RunDetail.MachineTypeDescriptor(id: "type-2", name: "Drink Machine", description: nil)

        let machineA = RunDetail.Machine(id: "machine-1", code: "A-101", description: "Lobby", machineType: snackType, location: downtown)
        let machineB = RunDetail.Machine(id: "machine-2", code: "B-204", description: "Breakroom", machineType: snackType, location: downtown)
        let machineC = RunDetail.Machine(id: "machine-3", code: "C-08", description: "Front Vestibule", machineType: drinkType, location: uptown)

        let coilA = RunDetail.Coil(id: "coil-1", code: "C1", machineId: machineA.id)
        let coilB = RunDetail.Coil(id: "coil-2", code: "C2", machineId: machineB.id)
        let coilC = RunDetail.Coil(id: "coil-3", code: "C3", machineId: machineC.id)

        let coilItemA = RunDetail.CoilItem(id: "coil-item-1", par: 10, coil: coilA)
        let coilItemB = RunDetail.CoilItem(id: "coil-item-2", par: 8, coil: coilB)
        let coilItemC = RunDetail.CoilItem(id: "coil-item-3", par: 12, coil: coilC)

        let skuSnack = RunDetail.Sku(id: "sku-1", code: "SKU-001", name: "Trail Mix", type: "Snack", isCheeseAndCrackers: false, countNeededPointer: "total")
        let skuDrink = RunDetail.Sku(id: "sku-2", code: "SKU-002", name: "Sparkling Water", type: "Beverage", isCheeseAndCrackers: false, countNeededPointer: "par")
        let skuCheese = RunDetail.Sku(id: "sku-3", code: "SKU-003", name: "Cheese & Crackers", type: "Snack", isCheeseAndCrackers: true, countNeededPointer: "current")

        let pickA = RunDetail.PickItem(id: "pick-1", count: 6, current: 8, par: 10, need: 6, forecast: 7, total: 12, status: "PICKED", pickedAt: Date(), coilItem: coilItemA, sku: skuSnack, machine: machineA, location: downtown)
        let pickB = RunDetail.PickItem(id: "pick-2", count: 4, current: 3, par: 8, need: 4, forecast: 5, total: 9, status: "PENDING", pickedAt: nil, coilItem: coilItemB, sku: skuCheese, machine: machineB, location: downtown)
        let pickC = RunDetail.PickItem(id: "pick-3", count: 9, current: 11, par: 15, need: 9, forecast: 10, total: 18, status: "PICKED", pickedAt: Date().addingTimeInterval(-1200), coilItem: coilItemC, sku: skuDrink, machine: machineC, location: uptown)

        let chocolateBox1 = RunDetail.ChocolateBox(id: "box-1", number: 1, machine: machineA)
        let chocolateBox2 = RunDetail.ChocolateBox(id: "box-2", number: 34, machine: machineB)
        let chocolateBox3 = RunDetail.ChocolateBox(id: "box-3", number: 5, machine: nil)

        let locationOrders = [
            RunDetail.LocationOrder(id: "order-1", locationId: downtown.id, position: 0),
            RunDetail.LocationOrder(id: "order-2", locationId: uptown.id, position: 1)
        ]

        return RunDetail(
            id: runId,
            status: "PICKING",
            companyId: "company-1",
            scheduledFor: Date().addingTimeInterval(3600),
            pickingStartedAt: Date().addingTimeInterval(-1800),
            pickingEndedAt: nil,
            createdAt: Date().addingTimeInterval(-7200),
            picker: RunParticipant(id: "picker-1", firstName: "Jordan", lastName: "Smith"),
            runner: nil,
            locations: [downtown, uptown],
            machines: [machineA, machineB, machineC],
            pickItems: [pickA, pickB, pickC],
            chocolateBoxes: [chocolateBox1, chocolateBox2, chocolateBox3],
            locationOrders: locationOrders
        )
    }
    
    func assignUser(to runId: String, userId: String, role: String, credentials: AuthCredentials) async throws {
        // Preview does nothing
    }
    
    func fetchCompanyUsers(credentials: AuthCredentials) async throws -> [CompanyUser] {
        return [
            CompanyUser(id: "user-1", email: "jordan@example.com", firstName: "Jordan", lastName: "Smith", phone: nil, role: "PICKER"),
            CompanyUser(id: "user-2", email: "alex@example.com", firstName: "Alex", lastName: "Johnson", phone: nil, role: "RUNNER"),
            CompanyUser(id: "user-3", email: "sam@example.com", firstName: "Sam", lastName: "Brown", phone: nil, role: "PICKER")
        ]
    }
    
    func updatePickItemStatuses(runId: String, pickIds: [String], status: String, credentials: AuthCredentials) async throws {
        // Preview does nothing
    }
    
    func deletePickItem(runId: String, pickId: String, credentials: AuthCredentials) async throws {
        // Preview does nothing
    }

    func deletePickEntries(for runId: String, locationID: String, credentials: AuthCredentials) async throws {
        // Preview does nothing
    }
    
    func updateRunStatus(runId: String, status: String, credentials: AuthCredentials) async throws {
        // Preview does nothing
    }
    
    func fetchChocolateBoxes(for runId: String, credentials: AuthCredentials) async throws -> [RunDetail.ChocolateBox] {
        let downtown = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
        let snackType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
        let drinkType = RunDetail.MachineTypeDescriptor(id: "type-2", name: "Drink Machine", description: "Cold beverages")
        let machineA = RunDetail.Machine(id: "machine-1", code: "A-101", description: "Lobby", machineType: snackType, location: downtown)
        let machineB = RunDetail.Machine(id: "machine-2", code: "B-204", description: "Breakroom", machineType: drinkType, location: downtown)
        
        let chocolateBox1 = RunDetail.ChocolateBox(id: "box-1", number: 1, machine: machineA)
        let chocolateBox2 = RunDetail.ChocolateBox(id: "box-2", number: 34, machine: machineB)
        let chocolateBox3 = RunDetail.ChocolateBox(id: "box-3", number: 5, machine: nil)
        
        return [chocolateBox1, chocolateBox2, chocolateBox3]
    }
    
    func createChocolateBox(for runId: String, number: Int, machineId: String, credentials: AuthCredentials) async throws -> RunDetail.ChocolateBox {
        let downtown = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
        let snackType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
        let machineA = RunDetail.Machine(id: machineId, code: "A-101", description: "Lobby", machineType: snackType, location: downtown)
        
        return RunDetail.ChocolateBox(id: "new-box", number: number, machine: machineA)
    }
    
    func updateChocolateBox(for runId: String, boxId: String, number: Int?, machineId: String?, credentials: AuthCredentials) async throws -> RunDetail.ChocolateBox {
        let downtown = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
        let snackType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
        let machineA = RunDetail.Machine(id: machineId ?? "machine-1", code: "A-101", description: "Lobby", machineType: snackType, location: downtown)
        
        return RunDetail.ChocolateBox(id: boxId, number: number ?? 1, machine: machineA)
    }
    
    func deleteChocolateBox(for runId: String, boxId: String, credentials: AuthCredentials) async throws {
        // Preview does nothing
    }
    
    func updateSkuCheeseStatus(skuId: String, isCheeseAndCrackers: Bool, credentials: AuthCredentials) async throws {
        // Preview does nothing
    }
    
    func updateSkuCountPointer(skuId: String, countNeededPointer: String, credentials: AuthCredentials) async throws {
        // Preview does nothing
    }
    
    func deleteRun(runId: String, credentials: AuthCredentials) async throws {
        // Preview does nothing
    }
    
    func fetchAudioCommands(for runId: String, credentials: AuthCredentials) async throws -> AudioCommandsResponse {
        // Return sample audio commands for preview with location ordering
        let locationCommand1 = AudioCommandsResponse.AudioCommand(
            id: "location-1",
            audioCommand: "Location Downtown HQ",
            pickEntryIds: [],
            type: "location",
            locationName: "Downtown HQ",
            machineName: nil,
            machineId: nil,
            skuName: nil,
            skuCode: nil,
            count: 0,
            coilCode: nil,
            coilCodes: nil,
            order: 0
        )
        
        let machineCommand1 = AudioCommandsResponse.AudioCommand(
            id: "machine-1",
            audioCommand: "Machine A-101",
            pickEntryIds: [],
            type: "machine",
            locationName: nil,
            machineName: "A-101",
            machineId: "machine-1",
            skuName: nil,
            skuCode: nil,
            count: 0,
            coilCode: nil,
            coilCodes: nil,
            order: 1
        )
        
        let itemCommand1 = AudioCommandsResponse.AudioCommand(
            id: "pick-1",
            audioCommand: "Trail Mix, Snack. Need 6. For 3 coils.",
            pickEntryIds: ["pick-1", "pick-1b", "pick-1c"], // Example of grouped entries
            type: "item",
            locationName: nil,
            machineName: "A-101",
            machineId: "machine-1",
            skuName: "Trail Mix",
            skuCode: "SKU-001",
            count: 6,
            coilCode: "3 coils",
            coilCodes: ["E7", "E6", "D2"], // Example of multiple coils
            order: 2
        )
        
        let machineCommand2 = AudioCommandsResponse.AudioCommand(
            id: "machine-2",
            audioCommand: "Machine B-204",
            pickEntryIds: [],
            type: "machine",
            locationName: nil,
            machineName: "B-204",
            machineId: "machine-2",
            skuName: nil,
            skuCode: nil,
            count: 0,
            coilCode: nil,
            coilCodes: nil,
            order: 3
        )
        
        let itemCommand2 = AudioCommandsResponse.AudioCommand(
            id: "pick-2",
            audioCommand: "Cheese & Crackers, Snack. Need 4. Coil C2.",
            pickEntryIds: ["pick-2"],
            type: "item",
            locationName: nil,
            machineName: "B-204",
            machineId: "machine-2",
            skuName: "Cheese & Crackers",
            skuCode: "SKU-003",
            count: 4,
            coilCode: "C2",
            coilCodes: nil, // Single coil example
            order: 4
        )
        
        let locationCommand2 = AudioCommandsResponse.AudioCommand(
            id: "location-2",
            audioCommand: "Location Uptown Annex",
            pickEntryIds: [],
            type: "location",
            locationName: "Uptown Annex",
            machineName: nil,
            machineId: nil,
            skuName: nil,
            skuCode: nil,
            count: 0,
            coilCode: nil,
            coilCodes: nil,
            order: 5
        )
        
        let machineCommand3 = AudioCommandsResponse.AudioCommand(
            id: "machine-3",
            audioCommand: "Machine C-08",
            pickEntryIds: [],
            type: "machine",
            locationName: nil,
            machineName: "C-08",
            machineId: "machine-3",
            skuName: nil,
            skuCode: nil,
            count: 0,
            coilCode: nil,
            coilCodes: nil,
            order: 6
        )
        
        let itemCommand3 = AudioCommandsResponse.AudioCommand(
            id: "pick-3",
            audioCommand: "Sparkling Water, Beverage. Need 9. Coil C3.",
            pickEntryIds: ["pick-3", "pick-3a", "pick-3b"], // Example of grouped entries
            type: "item",
            locationName: nil,
            machineName: "C-08",
            machineId: "machine-3",
            skuName: "Sparkling Water",
            skuCode: "SKU-002",
            count: 9,
            coilCode: "C3",
            coilCodes: nil, // Single coil example
            order: 7
        )
        
        let commands = [locationCommand1, machineCommand1, itemCommand1, machineCommand2, itemCommand2, locationCommand2, machineCommand3, itemCommand3]
        let itemCommands = commands.filter { $0.type == "item" }
        
        return AudioCommandsResponse(
            runId: runId,
            audioCommands: commands,
            totalItems: itemCommands.count,
            hasItems: !itemCommands.isEmpty
        )
    }

    func updateLocationOrder(for runId: String, orderedLocationIds: [String?], credentials: AuthCredentials) async throws -> [RunDetail.LocationOrder] {
        orderedLocationIds.enumerated().map { index, identifier in
            RunDetail.LocationOrder(id: "order-\(index + 1)", locationId: identifier, position: index)
        }
    }
}

extension RunSummary {
    static var previewReady: RunSummary {
        RunSummary(
            id: "run-ready",
            status: "READY",
            scheduledFor: previewDate(hour: 9, minute: 30),
            pickingStartedAt: nil,
            pickingEndedAt: nil,
            createdAt: previewDate(hour: 8, minute: 15),
            locationCount: 3,
            chocolateBoxes: [
                RunSummary.ChocolateBox(id: "box-1", number: 1, machine: nil),
                RunSummary.ChocolateBox(id: "box-2", number: 3, machine: nil)
            ],
            picker: RunSummary.Participant(
                id: "picker-1",
                firstName: "Jordan",
                lastName: "Smith"
            ),
            runner: nil
        )
    }

    static var previewPicking: RunSummary {
        RunSummary(
            id: "run-picking",
            status: "PICKING",
            scheduledFor: previewDate(hour: 10, minute: 45),
            pickingStartedAt: previewDate(hour: 10, minute: 30),
            pickingEndedAt: nil,
            createdAt: previewDate(hour: 9, minute: 0),
            locationCount: 5,
            chocolateBoxes: [
                RunSummary.ChocolateBox(id: "box-3", number: 2, machine: nil),
                RunSummary.ChocolateBox(id: "box-4", number: 7, machine: nil),
                RunSummary.ChocolateBox(id: "box-5", number: 12, machine: nil)
            ],
            picker: RunSummary.Participant(
                id: "picker-2",
                firstName: "Riley",
                lastName: "Chen"
            ),
            runner: RunSummary.Participant(
                id: "runner-1",
                firstName: "Morgan",
                lastName: "Lee"
            )
        )
    }

    static var previewPicked: RunSummary {
        RunSummary(
            id: "run-picked",
            status: "PICKED",
            scheduledFor: previewDate(hour: 12, minute: 0),
            pickingStartedAt: previewDate(hour: 11, minute: 10),
            pickingEndedAt: previewDate(hour: 11, minute: 48),
            createdAt: previewDate(hour: 9, minute: 45),
            locationCount: 2,
            chocolateBoxes: [
                RunSummary.ChocolateBox(id: "box-6", number: 5, machine: nil)
            ],
            picker: RunSummary.Participant(
                id: "picker-3",
                firstName: "Cameron",
                lastName: "Diaz"
            ),
            runner: RunSummary.Participant(
                id: "runner-2",
                firstName: "Alex",
                lastName: "Johnson"
            )
        )
    }

    private static func previewDate(hour: Int, minute: Int) -> Date {
        let components = DateComponents(year: 2025, month: 11, day: 6, hour: hour, minute: minute)
        return Calendar(identifier: .gregorian).date(from: components) ?? .now
    }
}
