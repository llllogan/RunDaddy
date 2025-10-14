//
//  Run.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation
import SwiftData

@Model
final class Run {
    @Attribute(.unique) var id: String
    var runner: String
    var date: Date
    @Relationship(deleteRule: .cascade) var runCoils: [RunCoil] = []

    init(id: String, runner: String, date: Date, runCoils: [RunCoil] = []) {
        self.id = id
        self.runner = runner
        self.date = date
        self.runCoils = runCoils
    }
}
