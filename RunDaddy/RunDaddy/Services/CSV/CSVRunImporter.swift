//
//  CSVRunImporter.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation

struct CSVRunImporter {
    struct RunLocationPayload {
        let runner: String
        let date: Date
        let location: LocationPayload
        let machines: [MachinePayload]
        let items: [ItemPayload]
        let coils: [CoilPayload]
        let runCoils: [RunCoilPayload]
    }

    struct LocationPayload {
        let id: String
        let name: String
        let address: String
    }

    struct MachinePayload {
        let id: String
        let name: String
        let locationID: String
        let locationLabel: String?
    }

    struct ItemPayload {
        let id: String
        let name: String
        let type: String
    }

    struct CoilPayload {
        let id: String
        let machineID: String
        let itemID: String
        var machinePointer: Int64
        var stockLimit: Int64
    }

    struct RunCoilPayload {
        let id: String
        let coilID: String
        let pick: Int64
    }

    enum ImportError: LocalizedError {
        case emptyFile
        case missingLocationHeader
        case invalidLocationHeader(String)
        case invalidDate(String)
        case missingMachineHeader
        case invalidMachineHeader(String)
        case missingMachineName(String)
        case missingItemTable(String)

        var errorDescription: String? {
            switch self {
            case .emptyFile:
                return "The selected CSV is empty."
            case .missingLocationHeader:
                return "The CSV does not contain a location header."
            case let .invalidLocationHeader(value):
                return "Unable to parse the location information from \"\(value)\"."
            case let .invalidDate(value):
                return "Unable to parse the date \"\(value)\" in the CSV."
            case .missingMachineHeader:
                return "No machine sections were found in the CSV."
            case let .invalidMachineHeader(value):
                return "Unable to parse machine details from \"\(value)\"."
            case let .missingMachineName(machineID):
                return "The CSV does not include a machine name for \(machineID)."
            case let .missingItemTable(machineID):
                return "Missing the item table for machine \(machineID)."
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_AU_POSIX")
        return formatter
    }()

    func loadLocation(from url: URL) throws -> RunLocationPayload {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try parseLocation(contents: contents, fileName: url.deletingPathExtension().lastPathComponent)
    }

    private func parseLocation(contents: String, fileName: String) throws -> RunLocationPayload {
        let rows = parseCSVRows(from: contents)
        guard !rows.isEmpty else {
            throw ImportError.emptyFile
        }

        var index = 0

        guard let locationIndex = nextNonEmptyIndex(startingAt: index, in: rows) else {
            throw ImportError.missingLocationHeader
        }

        index = locationIndex
        let locationText = sanitize(rows[index].first ?? "")
        guard locationText.lowercased().hasPrefix("location:") else {
            throw ImportError.invalidLocationHeader(locationText)
        }

        let (locationName, dateString) = try parseLocationHeader(locationText)
        guard let runDate = CSVRunImporter.dateFormatter.date(from: dateString) else {
            throw ImportError.invalidDate(dateString)
        }

        let addressCandidateIndex = nextNonEmptyIndex(startingAt: index + 1, in: rows)
        var locationAddress = ""

        if let candidateIndex = addressCandidateIndex {
            index = candidateIndex
            let candidateRow = rows[candidateIndex]
            let candidateValue = stripQuotes(from: sanitize(candidateRow.first(where: { !sanitize($0).isEmpty }) ?? ""))

            let isMachineHeader = parseMachineID(from: candidateValue) != nil
            let isNextLocationHeader = candidateValue.lowercased().hasPrefix("location:")

            if !candidateValue.isEmpty, !isMachineHeader, !isNextLocationHeader {
                locationAddress = candidateValue
                index = candidateIndex + 1
            }
        } else {
            index = locationIndex + 1
        }

        let locationPayload = LocationPayload(id: slug(from: locationName),
                                              name: locationName,
                                              address: locationAddress)

        var machines: [MachinePayload] = []
        var itemsByID: [String: ItemPayload] = [:]
        var coilsByID: [String: CoilPayload] = [:]
        var runCoils: [RunCoilPayload] = []

        let sanitizedRunner = sanitize(fileName)
        let runner = sanitizedRunner.isEmpty ? fileName : sanitizedRunner

        parsingLoop: while index < rows.count {
            guard let machineHeaderIndex = nextMachineHeaderIndex(startingAt: index, in: rows) else {
                break
            }

            index = machineHeaderIndex
            let machineHeaderText = sanitize(rows[index].first ?? "")
            guard let machineID = parseMachineID(from: machineHeaderText) else {
                throw ImportError.invalidMachineHeader(machineHeaderText)
            }

            guard let machineNameIndex = nextNonEmptyIndex(startingAt: index + 1, in: rows) else {
                throw ImportError.missingMachineName(machineID)
            }

            index = machineNameIndex
            var rawMachineName = stripQuotes(from: sanitize(rows[index].first ?? ""))
            rawMachineName = stripDateParenthetical(from: rawMachineName)
            if rawMachineName.isEmpty {
                throw ImportError.missingMachineName(machineID)
            }

            let machinePayload = MachinePayload(id: machineID,
                                                name: rawMachineName,
                                                locationID: locationPayload.id,
                                                locationLabel: locationPayload.name)
            machines.append(machinePayload)

            guard let tableHeaderIndex = nextTableHeaderIndex(startingAt: index + 1, in: rows) else {
                throw ImportError.missingItemTable(machineID)
            }

            index = tableHeaderIndex + 1

            while index < rows.count {
                let row = rows[index]
                let firstColumn = sanitize(row.first ?? "")

                if firstColumn.lowercased().hasPrefix("location:") {
                    break parsingLoop
                }

                if firstColumn.localizedCaseInsensitiveContains("machine"),
                   !firstColumn.isEmpty {
                    break
                }

                if firstColumn.caseInsensitiveCompare("short") == .orderedSame {
                    index += 1
                    continue
                }

                if row.allSatisfy({ sanitize($0).isEmpty }) {
                    if let nextIndex = nextNonEmptyIndex(startingAt: index + 1, in: rows) {
                        let preview = sanitize(rows[nextIndex].first ?? "")
                        if preview.localizedCaseInsensitiveContains("machine") {
                            index = nextIndex
                            break
                        }
                        index = nextIndex
                        continue
                    } else {
                        index = rows.count
                        break
                    }
                }

                guard row.count >= 9 else {
                    index += 1
                    continue
                }

                let coilPointerValue = sanitize(row[safe: 4] ?? "")
                let itemNameValue = stripQuotes(from: sanitize(row[safe: 5] ?? ""))

                if itemNameValue.isEmpty {
                    index += 1
                    continue
                }

                let parValue = parseInt64(from: sanitize(row[safe: 7] ?? ""))
                let needValue = parseInt64(from: sanitize(row[safe: 8] ?? ""))
                let machinePointer = parseInt64(from: coilPointerValue)

                let itemComponents = parseItemNameComponents(from: itemNameValue)
                let itemID = itemComponents.id
                let itemName = itemComponents.name
                let itemType = itemComponents.type

                if itemsByID[itemID] == nil {
                    itemsByID[itemID] = ItemPayload(id: itemID, name: itemName, type: itemType)
                }

                let coilID = coilIdentifier(machineID: machineID, pointer: machinePointer, itemID: itemID)
                if var existingCoil = coilsByID[coilID] {
                    existingCoil.machinePointer = machinePointer
                    existingCoil.stockLimit = parValue
                    coilsByID[coilID] = existingCoil
                } else {
                    let coilPayload = CoilPayload(id: coilID,
                                                  machineID: machineID,
                                                  itemID: itemID,
                                                  machinePointer: machinePointer,
                                                  stockLimit: parValue)
                    coilsByID[coilID] = coilPayload
                }

                if needValue > 0 {
                    let runCoilPayload = RunCoilPayload(id: UUID().uuidString,
                                                        coilID: coilID,
                                                        pick: needValue)
                    runCoils.append(runCoilPayload)
                }

                index += 1
            }
        }

        guard !machines.isEmpty else {
            throw ImportError.missingMachineHeader
        }

        return RunLocationPayload(runner: runner,
                                  date: runDate,
                                  location: locationPayload,
                                  machines: machines,
                                  items: Array(itemsByID.values),
                                  coils: Array(coilsByID.values),
                                  runCoils: runCoils)
    }

    private func parseLocationHeader(_ value: String) throws -> (name: String, date: String) {
        let trimmed = value.replacingOccurrences(of: "Location:", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let openParen = trimmed.lastIndex(of: "("),
              let closeParen = trimmed.lastIndex(of: ")"),
              openParen < closeParen else {
            throw ImportError.invalidLocationHeader(value)
        }

        let name = trimmed[..<openParen].trimmingCharacters(in: .whitespacesAndNewlines)
        let date = trimmed[trimmed.index(after: openParen)..<closeParen]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !date.isEmpty else {
            throw ImportError.invalidLocationHeader(value)
        }

        return (String(name), String(date))
    }

    private func parseMachineID(from value: String) -> String? {
        guard let machineRange = value.range(of: "Machine", options: [.caseInsensitive]) else {
            return nil
        }

        let suffix = value[machineRange.upperBound...]
        guard let idStart = suffix.firstIndex(where: { !$0.isWhitespace && $0 != "-" }) else {
            return nil
        }

        let remainder = suffix[idStart...]
        let idEnd = remainder.firstIndex(where: { $0.isWhitespace || $0 == "," }) ?? remainder.endIndex

        let rawID = suffix[idStart..<idEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        return rawID.isEmpty ? nil : rawID
    }

    private func nextNonEmptyIndex(startingAt index: Int, in rows: [[String]]) -> Int? {
        var current = index

        while current < rows.count {
            if rows[current].contains(where: { !sanitize($0).isEmpty }) {
                return current
            }
            current += 1
        }

        return nil
    }

    private func nextMachineHeaderIndex(startingAt index: Int, in rows: [[String]]) -> Int? {
        var current = index
        while current < rows.count {
            let value = sanitize(rows[current].first ?? "")
            if value.localizedCaseInsensitiveContains("machine") {
                return current
            }
            current += 1
        }
        return nil
    }

    private func nextTableHeaderIndex(startingAt index: Int, in rows: [[String]]) -> Int? {
        var current = index
        while current < rows.count {
            let value = sanitize(rows[current].first ?? "")
            if value.caseInsensitiveCompare("Short") == .orderedSame {
                return current
            }
            current += 1
        }
        return nil
    }

    private func parseInt64(from value: String) -> Int64 {
        let cleaned = value.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty, cleaned != "-", cleaned.lowercased() != "na" else {
            return 0
        }

        if let intValue = Int64(cleaned) {
            return intValue
        }

        if let doubleValue = Double(cleaned) {
            return Int64(doubleValue)
        }

        return 0
    }

    private func parseItemNameComponents(from value: String) -> (id: String, name: String, type: String) {
        let segments = value.split(separator: "-", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let first = segments.first, !first.isEmpty else {
            return (id: slug(from: value), name: value, type: "")
        }

        let id = String(first)
        if segments.count >= 3 {
            let name = segments[1..<segments.count - 1].joined(separator: " - ")
            let type = String(segments.last ?? "")
            return (id: id, name: name, type: type)
        } else if segments.count == 2 {
            return (id: id, name: segments[1], type: "")
        } else {
            return (id: id, name: id, type: "")
        }
    }

    private func coilIdentifier(machineID: String, pointer: Int64, itemID: String) -> String {
        "\(machineID)-\(pointer)-\(itemID)"
    }

    private func sanitize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{feff}", with: "")
    }

    private func stripQuotes(from value: String) -> String {
        guard value.first == "\"", value.last == "\"" else {
            return value
        }

        return String(value.dropFirst().dropLast())
    }

    private func stripDateParenthetical(from value: String) -> String {
        guard let open = value.lastIndex(of: "("),
              let close = value.lastIndex(of: ")"),
              open < close else {
            return value
        }

        let inner = value[value.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
        if CSVRunImporter.dateFormatter.date(from: inner) != nil {
            return value[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value
    }

    private func slug(from value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.uppercased().unicodeScalars.filter { allowed.contains($0) }
        return scalars.isEmpty ? UUID().uuidString : String(String.UnicodeScalarView(scalars))
    }

    private func parseCSVRows(from text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isQuoted = false

        let scalars = Array(text.unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            switch scalar {
            case "\"":
                if isQuoted, (index + 1) < scalars.count, scalars[index + 1] == "\"" {
                    currentField.append("\"")
                    index += 1
                } else {
                    isQuoted.toggle()
                }
            case ",":
                if isQuoted {
                    currentField.append(Character(scalar))
                } else {
                    currentRow.append(currentField)
                    currentField.removeAll(keepingCapacity: false)
                }
            case "\n":
                if isQuoted {
                    currentField.append(Character(scalar))
                } else {
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow.removeAll(keepingCapacity: false)
                    currentField.removeAll(keepingCapacity: false)
                }
            case "\r":
                if isQuoted {
                    currentField.append(Character(scalar))
                } else {
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow.removeAll(keepingCapacity: false)
                    currentField.removeAll(keepingCapacity: false)

                    if (index + 1) < scalars.count, scalars[index + 1] == "\n" {
                        index += 1
                    }
                }
            default:
                currentField.append(Character(scalar))
            }

            index += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}
