//
//  MailIntegrationSheet.swift
//  RunDaddy
//
//  Created by Codex on 12/10/2025.
//

import SwiftUI

struct MailIntegrationSheet: View {
    @ObservedObject var viewModel: MailIntegrationViewModel
    let webhookURL: String
    let apiKey: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Google Sheets")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button("Refresh") {
                            Task {
                                await viewModel.refresh(webhookURL: webhookURL, apiKey: apiKey)
                            }
                        }
                        .disabled(viewModel.isLoading)
                    }
                }
                .task {
                    await viewModel.refresh(webhookURL: webhookURL, apiKey: apiKey)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("Loading spreadsheets…")
        } else if let message = viewModel.errorMessage {
            VStack(spacing: 16) {
                Text(message)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    viewModel.clearError()
                    Task {
                        await viewModel.refresh(webhookURL: webhookURL, apiKey: apiKey)
                    }
                }
                .disabled(viewModel.isLoading)
            }
            .padding()
        } else if viewModel.spreadsheets.isEmpty {
            ContentUnavailableView("No spreadsheets",
                                   systemImage: "tablecells",
                                   description: Text("Try refreshing or check your integration settings."))
        } else {
            List(viewModel.spreadsheets, id: \.id) { spreadsheet in
                GoogleSpreadsheetRow(spreadsheet: spreadsheet)
                    .padding(.vertical, 8)
            }
            .listStyle(.insetGrouped)
        }
    }
}

private struct GoogleSpreadsheetRow: View {
    let spreadsheet: GoogleSpreadsheet

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(spreadsheet.name)
                .font(.headline)
            Text("Created: \(spreadsheet.dateCreated.formatted(.dateTime.year().month().day().hour().minute()))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Owner: \(spreadsheet.ownerEmail)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    MailIntegrationSheet(viewModel: MailIntegrationViewModel(),
                         webhookURL: "https://example.com",
                         apiKey: "test")
}

#Preview("Spreadsheet Row") {
    List {
        GoogleSpreadsheetRow(spreadsheet: .preview)
    }
    .listStyle(.insetGrouped)
}

private extension GoogleSpreadsheet {
    static let preview = GoogleSpreadsheet(id: "sample-sheet-id",
                                           name: "RunDaddy - Buggy",
                                           url: URL(string: "https://docs.google.com/spreadsheets/d/1Ba9NSw1jozlcasd3OZ-9LaDFXOHEr98iSrS-tPRTK8w/edit")!,
                                           ownerEmail: "loganjanssen02@gmail.com",
                                           dateCreated: Date(timeIntervalSince1970: 1_756_934_108))
}
