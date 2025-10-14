//
//  RunCoil.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation
import SwiftData

@Model
final class RunCoil {
    @Attribute(.unique) var id: String
    var pick: Int64
    var packOrder: Int64
    @Relationship(inverse: \Run.runCoils) var run: Run
    @Relationship(inverse: \Coil.runCoils) var coil: Coil

    init(id: String, pick: Int64, packOrder: Int64, run: Run, coil: Coil) {
        self.id = id
        self.pick = pick
        self.packOrder = packOrder
        self.run = run
        self.coil = coil
    }
}
