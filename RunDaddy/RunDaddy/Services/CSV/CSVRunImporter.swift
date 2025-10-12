//
//  CSVRunImporter.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import Foundation

struct CSVRunImporter {
    struct RunPayload {
        let name: String
        let items: [InventoryItemPayload]
    }

    struct InventoryItemPayload {
        let code: String
        let name: String
        let count: Int
        let category: String
    }

    enum ImportError: LocalizedError {
        case emptyFile
        case invalidHeader(expected: [String], found: [String])
        case malformedRow(line: Int)
        case invalidNeedValue(line: Int, value: String)
        case noData

        var errorDescription: String? {
            switch self {
            case .emptyFile:
                return "The selected CSV is empty."
            case let .invalidHeader(expected, found):
                let expectedList = expected.joined(separator: ", ")
                let foundList = found.joined(separator: ", ")
                return "Unexpected CSV headers. Expected \(expectedList), but found \(foundList)."
            case let .malformedRow(line):
                return "The CSV has a malformed row at line \(line)."
            case let .invalidNeedValue(line, value):
                return "The \"Need\" value \"\(value)\" at line \(line) could not be parsed as a number."
            case .noData:
                return "No items were found in the CSV."
            }
        }
    }

    private let expectedHeader = ["ItemCode", "ItemName", "Need", "Count", "Cases", "Category"]

    func loadRun(from url: URL) throws -> RunPayload {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try parse(contents: contents, runName: url.deletingPathExtension().lastPathComponent)
    }

    private func parse(contents: String, runName: String) throws -> RunPayload {
        let rows = parseCSVRows(from: contents)
        guard let headerRow = rows.first else {
            throw ImportError.emptyFile
        }

        let sanitizedHeader = headerRow.map { sanitize($0) }
        guard sanitizedHeader.count >= expectedHeader.count else {
            throw ImportError.invalidHeader(expected: expectedHeader, found: sanitizedHeader)
        }

        let headerPrefix = Array(sanitizedHeader.prefix(expectedHeader.count))
        guard headerPrefix == expectedHeader else {
            throw ImportError.invalidHeader(expected: expectedHeader, found: sanitizedHeader)
        }

        var items: [InventoryItemPayload] = []

        for (index, row) in rows.dropFirst().enumerated() {
            let lineNumber = index + 2 // account for header row

            if row.allSatisfy({ sanitize($0).isEmpty }) {
                continue
            }

            guard row.count >= expectedHeader.count else {
                throw ImportError.malformedRow(line: lineNumber)
            }

            let code = sanitize(row[0])
            let name = sanitize(row[1])
            let needValue = sanitize(row[2])
            let category = sanitize(row[5])

            guard !code.isEmpty || !name.isEmpty else {
                continue
            }

            let count = try parseCount(from: needValue, line: lineNumber)
            let payload = InventoryItemPayload(code: code,
                                               name: name,
                                               count: count,
                                               category: category)
            items.append(payload)
        }

        guard !items.isEmpty else {
            throw ImportError.noData
        }

        let normalizedRunName = sanitize(runName)
        let resolvedRunName = normalizedRunName.isEmpty ? runName : normalizedRunName

        return RunPayload(name: resolvedRunName, items: items)
    }

    private func parseCount(from value: String, line: Int) throws -> Int {
        if value.isEmpty {
            return 0
        }

        if let intValue = Int(value) {
            return intValue
        }

        if let doubleValue = Double(value) {
            return Int(doubleValue)
        }

        throw ImportError.invalidNeedValue(line: line, value: value)
    }

    private func sanitize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{feff}", with: "")
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
