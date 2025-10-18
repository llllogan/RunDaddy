//
//  GoogleSheetsService.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025. Updated by Codex.
//

import Foundation

protocol GoogleSheetsServicing {
    func fetchSpreadsheets(webhookURLString: String, apiKey: String) async throws -> [GoogleSpreadsheet]
    func exportSpreadsheet(webhookURLString: String,
                           apiKey: String,
                           sheetID: String,
                           recipientEmail: String) async throws -> GoogleSpreadsheetExportResponse
}

struct GoogleSpreadsheet: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let ownerEmail: String
    let dateCreated: Date
}

struct GoogleSpreadsheetResponse: Decodable {
    let action: String
    let total: Int
    let spreadsheets: [GoogleSpreadsheet]
}

enum GoogleSheetsServiceError: LocalizedError {
    case missingWebhookURL
    case missingAPIKey
    case missingRecipientEmail
    case missingSheetID
    case invalidWebhookURL
    case requestFailed(statusCode: Int)
    case unexpectedAction(String)
    case unexpectedExportAction(String)

    var errorDescription: String? {
        switch self {
        case .missingWebhookURL:
            return "Add a Google webhook URL in Settings first."
        case .missingAPIKey:
            return "Add an API key in Settings first."
        case .missingRecipientEmail:
            return "Add an email address in Settings first."
        case .missingSheetID:
            return "A spreadsheet identifier is required."
        case .invalidWebhookURL:
            return "The webhook URL is invalid."
        case .requestFailed(let statusCode):
            return "The Google webhook request failed with status code \(statusCode)."
        case .unexpectedAction(let action):
            return "Unexpected response action: \(action)."
        case .unexpectedExportAction(let action):
            return "Unexpected export response action: \(action)."
        }
    }
}

struct GoogleSheetsService: GoogleSheetsServicing {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchSpreadsheets(webhookURLString: String, apiKey: String) async throws -> [GoogleSpreadsheet] {
        let sanitizedURL = webhookURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitizedURL.isEmpty else {
            throw GoogleSheetsServiceError.missingWebhookURL
        }

        guard !sanitizedKey.isEmpty else {
            throw GoogleSheetsServiceError.missingAPIKey
        }

        guard let baseURL = URL(string: sanitizedURL) else {
            throw GoogleSheetsServiceError.invalidWebhookURL
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GoogleSheetsServiceError.invalidWebhookURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll(where: { $0.name == "action" || $0.name == "key" })
        queryItems.append(URLQueryItem(name: "action", value: "list"))
        queryItems.append(URLQueryItem(name: "key", value: sanitizedKey))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw GoogleSheetsServiceError.invalidWebhookURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleSheetsServiceError.requestFailed(statusCode: -1)
        }

        guard httpResponse.statusCode == 200 else {
            throw GoogleSheetsServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(GoogleSpreadsheetResponse.self, from: data)
        guard payload.action == "list" else {
            throw GoogleSheetsServiceError.unexpectedAction(payload.action)
        }

        return payload.spreadsheets
    }

    func exportSpreadsheet(webhookURLString: String,
                           apiKey: String,
                           sheetID: String,
                           recipientEmail: String) async throws -> GoogleSpreadsheetExportResponse {
        let sanitizedURL = webhookURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedSheetID = sheetID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedRecipient = recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitizedURL.isEmpty else {
            throw GoogleSheetsServiceError.missingWebhookURL
        }

        guard !sanitizedKey.isEmpty else {
            throw GoogleSheetsServiceError.missingAPIKey
        }

        guard !sanitizedRecipient.isEmpty else {
            throw GoogleSheetsServiceError.missingRecipientEmail
        }

        guard !sanitizedSheetID.isEmpty else {
            throw GoogleSheetsServiceError.missingSheetID
        }

        guard let baseURL = URL(string: sanitizedURL) else {
            throw GoogleSheetsServiceError.invalidWebhookURL
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GoogleSheetsServiceError.invalidWebhookURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll(where: { ["action", "sheetId", "recipient", "key"].contains($0.name) })
        queryItems.append(URLQueryItem(name: "action", value: "export"))
        queryItems.append(URLQueryItem(name: "sheetId", value: sanitizedSheetID))
        queryItems.append(URLQueryItem(name: "recipient", value: sanitizedRecipient))
        queryItems.append(URLQueryItem(name: "key", value: sanitizedKey))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw GoogleSheetsServiceError.invalidWebhookURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleSheetsServiceError.requestFailed(statusCode: -1)
        }

        guard httpResponse.statusCode == 200 else {
            throw GoogleSheetsServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(GoogleSpreadsheetExportResponse.self, from: data)
        guard payload.action == "export" else {
            throw GoogleSheetsServiceError.unexpectedExportAction(payload.action)
        }
        return payload
    }
}

struct GoogleSpreadsheetExportSummary: Decodable, Hashable {
    let id: String
    let name: String
    let url: URL
    let tabCount: Int
    let tabs: [String]
    let archiveName: String
}

struct GoogleSpreadsheetExportResponse: Decodable, Hashable, Identifiable {
    let recipient: String
    let spreadsheet: GoogleSpreadsheetExportSummary
    let action: String

    var id: String { spreadsheet.id }
}
