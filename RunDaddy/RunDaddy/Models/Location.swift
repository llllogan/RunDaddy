//
//  Location.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation
import SwiftData

@Model
final class Location {
    @Attribute(.unique) var id: String
    var name: String
    var address: String
    @Relationship(deleteRule: .cascade) var machines: [Machine] = []

    init(id: String, name: String, address: String, machines: [Machine] = []) {
        self.id = id
        self.name = name
        self.address = address
        self.machines = machines
    }
}
