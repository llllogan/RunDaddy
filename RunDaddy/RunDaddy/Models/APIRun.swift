//
//  APIRun.swift
//  RunDaddy
//
//  Created by opencode on 2025-11-03.
//

import Foundation

struct APIRun: Codable, Identifiable {
    let id: String
    let companyId: String
    let companyName: String
    let status: String
    let scheduledFor: Date?
    let pickingStartedAt: Date?
    let pickingEndedAt: Date?
    let createdAt: Date
    let pickerId: String?
    let pickerFirstName: String?
    let pickerLastName: String?
    let runnerId: String?
    let runnerFirstName: String?
    let runnerLastName: String?

    var pickerFullName: String? {
        guard let firstName = pickerFirstName, let lastName = pickerLastName else { return nil }
        return "\(firstName) \(lastName)"
    }

    var runnerFullName: String? {
        guard let firstName = runnerFirstName, let lastName = runnerLastName else { return nil }
        return "\(firstName) \(lastName)"
    }
}

