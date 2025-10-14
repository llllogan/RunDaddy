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
    var packed: Bool
    @Relationship(inverse: \Run.runCoils) var run: Run
    @Relationship(inverse: \Coil.runCoils) var coil: Coil

    init(id: String,
         pick: Int64,
         packOrder: Int64,
         packed: Bool = false,
         run: Run,
         coil: Coil) {
        self.id = id
        self.pick = pick
        self.packOrder = packOrder
        self.packed = packed
        self.run = run
        self.coil = coil
    }
}
