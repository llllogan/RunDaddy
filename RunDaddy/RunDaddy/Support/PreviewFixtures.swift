//
//  PreviewFixtures.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation
import SwiftData

enum PreviewFixtures {
    private static let shared = makeFixtures()

    private struct FixtureBundle {
        let container: ModelContainer
        let runs: [Run]
    }

    private static func makeFixtures() -> FixtureBundle {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Run.self,
                                            RunCoil.self,
                                            Coil.self,
                                            Machine.self,
                                            Location.self,
                                            Item.self,
                                            configurations: configuration)
        let context = container.mainContext

        let locationA = Location(id: "LOC001", name: "Preview Warehouse", address: "123 Example Street")
        let machineA = Machine(id: "M001", name: "Preview Machine", locationLabel: "Preview Warehouse", location: locationA)
        let itemA = Item(id: "ITEM001", name: "Sample Snack", type: "Snack")
        let coilA = Coil(id: "M001-10", machinePointer: 10, stockLimit: 5, machine: machineA, item: itemA)

        let locationB = Location(id: "LOC002", name: "Preview Cafe", address: "456 Sample Road")
        let machineB = Machine(id: "M002", name: "Preview Freezer", locationLabel: "Preview Cafe", location: locationB)
        let itemB = Item(id: "ITEM002", name: "Frozen Treat", type: "Dessert")
        let coilB = Coil(id: "M002-04", machinePointer: 4, stockLimit: 8, machine: machineB, item: itemB)

        let run = Run(id: "RUN-PREVIEW", runner: "Preview Runner", date: Date())
        let runCoilA = RunCoil(id: "RUNCOIL-A", pick: 3, packOrder: 1, packed: false, run: run, coil: coilA)
        let runCoilB = RunCoil(id: "RUNCOIL-B", pick: 2, packOrder: 2, packed: false, run: run, coil: coilB)

        locationA.machines = [machineA]
        locationB.machines = [machineB]
        machineA.coils = [coilA]
        machineB.coils = [coilB]
        coilA.runCoils = [runCoilA]
        coilB.runCoils = [runCoilB]
        run.runCoils = [runCoilA, runCoilB]

        context.insert(locationA)
        context.insert(locationB)
        context.insert(machineA)
        context.insert(machineB)
        context.insert(itemA)
        context.insert(itemB)
        context.insert(coilA)
        context.insert(coilB)
        context.insert(run)
        context.insert(runCoilA)
        context.insert(runCoilB)

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to seed preview data: \(error)")
        }

        return FixtureBundle(container: container, runs: [run])
    }

    static var container: ModelContainer {
        shared.container
    }

    static var sampleRun: Run {
        shared.runs.first ?? Run(id: UUID().uuidString, runner: "Preview", date: Date())
    }
    static var sampleRunOptional: Run? {
        shared.runs.first
    }
}
