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

        let location = Location(id: "LOC001", name: "Preview Warehouse", address: "123 Example Street")
        let machine = Machine(id: "M001", name: "Preview Machine", locationLabel: "Preview Warehouse", location: location)
        let item = Item(id: "ITEM001", name: "Sample Snack", type: "Snack")
        let coil = Coil(id: "M001-10", machinePointer: 10, stockLimit: 5, machine: machine, item: item)
        let run = Run(id: "RUN-PREVIEW", runner: "Preview Runner", date: Date())
        let runCoil = RunCoil(id: "RUNCOIL-PREVIEW", pick: 3, packOrder: 1, run: run, coil: coil)

        location.machines = [machine]
        machine.coils = [coil]
        coil.runCoils = [runCoil]
        run.runCoils = [runCoil]

        context.insert(location)
        context.insert(machine)
        context.insert(item)
        context.insert(coil)
        context.insert(run)
        context.insert(runCoil)

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
}
