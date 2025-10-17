//
//  MailIntegrationViewModel.swift
//  RunDaddy
//
//  Created by Codex on 12/10/2025.
//

import Foundation
import Combine

@MainActor
final class MailIntegrationViewModel: ObservableObject {
    @Published private(set) var spreadsheets: [GoogleSpreadsheet] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let sheetsService: GoogleSheetsServicing

    init(sheetsService: GoogleSheetsServicing? = nil) {
        self.sheetsService = sheetsService ?? GoogleSheetsService()
    }

    func refresh(webhookURL: String, apiKey: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let results = try await sheetsService.fetchSpreadsheets(webhookURLString: webhookURL, apiKey: apiKey)
                .sorted(by: { $0.dateCreated > $1.dateCreated })
            spreadsheets = results
            errorMessage = results.isEmpty ? "No spreadsheets found." : nil
        } catch {
            spreadsheets = []
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
