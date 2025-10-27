//
//  RunDetailSections.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation

struct RunMachineSection: Identifiable {
    let machine: Machine
    let coils: [RunCoil]

    var id: String { machine.id }
    var coilCount: Int { coils.count }
    var itemCount: Int {
        coils.reduce(into: 0) { $0 += max(Int($1.pick), 0) }
    }
}

struct RunLocationSection: Identifiable {
    let location: Location
    let packOrder: Int
    let machines: [RunMachineSection]

    var id: String { location.id }
    var machineCount: Int { machines.count }
    var coilCount: Int { machines.reduce(into: 0) { $0 += $1.coilCount } }
    var itemCount: Int { machines.reduce(into: 0) { $0 += $1.itemCount } }
}

struct NotPackedLocationSection: Identifiable {
    let location: Location
    let items: [RunCoil]

    var id: String { location.id }
}

enum RunDetailFormatter {
    static func orderDescription(for packOrder: Int) -> String {
        guard packOrder > 0 else { return "Unscheduled" }
        if packOrder == 1 {
            return "1 (deliver last)"
        }
        return "\(packOrder)"
    }
}

enum RunDetailSectionsBuilder {
    static func locationSections(for run: Run) -> [RunLocationSection] {
        var byLocation: [String: [RunCoil]] = [:]

        for runCoil in run.runCoils {
            guard let location = runCoil.coil.machine.location else { continue }
            byLocation[location.id, default: []].append(runCoil)
        }

        return byLocation.compactMap { _, runCoils in
            guard let location = runCoils.first?.coil.machine.location else { return nil }

            let machines = Dictionary(grouping: runCoils) { $0.coil.machine.id }
                .compactMap { _, machineCoils -> RunMachineSection? in
                    guard let machine = machineCoils.first?.coil.machine else { return nil }
                    let sortedCoils = machineCoils.sorted { lhs, rhs in
                        if lhs.packOrder == rhs.packOrder {
                            return lhs.coil.machinePointer.localizedStandardCompare(rhs.coil.machinePointer) == .orderedAscending
                        }
                        return lhs.packOrder < rhs.packOrder
                    }
                    return RunMachineSection(machine: machine, coils: sortedCoils)
                }
                .sorted {
                    $0.machine.name.localizedCaseInsensitiveCompare($1.machine.name) == .orderedAscending
                }

            let locationOrder = runCoils.map { Int($0.packOrder) }.min() ?? Int.max
            let safeOrder = locationOrder == Int.max ? 0 : locationOrder
            return RunLocationSection(location: location,
                                      packOrder: safeOrder,
                                      machines: machines)
        }
        .sorted {
            if $0.packOrder == $1.packOrder {
                return $0.location.name.localizedCaseInsensitiveCompare($1.location.name) == .orderedAscending
            }
            return $0.packOrder < $1.packOrder
        }
    }

    static func notPackedSections(for run: Run) -> [NotPackedLocationSection] {
        let filtered = run.runCoils.filter { !$0.packed && $0.pick > 0 }
        var byLocation: [String: [RunCoil]] = [:]

        for runCoil in filtered {
            guard let location = runCoil.coil.machine.location else { continue }
            byLocation[location.id, default: []].append(runCoil)
        }

        return byLocation.compactMap { _, runCoils in
            guard let location = runCoils.first?.coil.machine.location else { return nil }

            let sortedItems = runCoils.sorted { lhs, rhs in
                let lhsMachine = lhs.coil.machine.name
                let rhsMachine = rhs.coil.machine.name
                if lhsMachine != rhsMachine {
                    return lhsMachine.localizedCaseInsensitiveCompare(rhsMachine) == .orderedAscending
                }
                return lhs.coil.machinePointer.localizedStandardCompare(rhs.coil.machinePointer) == .orderedAscending
            }

            return NotPackedLocationSection(location: location, items: sortedItems)
        }
        .sorted {
            $0.location.name.localizedCaseInsensitiveCompare($1.location.name) == .orderedAscending
        }
    }
}
