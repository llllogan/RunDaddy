//
//  Coil.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation
import SwiftData

@Model
final class Coil {
    @Attribute(.unique) var id: String
    var machinePointer: String
    var stockLimit: Int64
    @Relationship(inverse: \Machine.coils) var machine: Machine
    @Relationship(inverse: \Item.coils) var item: Item
    @Relationship(deleteRule: .cascade) var runCoils: [RunCoil] = []

    init(id: String,
         machinePointer: String,
         stockLimit: Int64,
         machine: Machine,
         item: Item,
         runCoils: [RunCoil] = []) {
        self.id = id
        self.machinePointer = machinePointer
        self.stockLimit = stockLimit
        self.machine = machine
        self.item = item
        self.runCoils = runCoils
    }
}
