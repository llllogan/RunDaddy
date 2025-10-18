//
//  MailIntegrationSheet.swift
//  RunDaddy
//
//  Created by Codex on 12/10/2025.
//

import SwiftUI
import Combine

struct MailIntegrationSheet: View {
    @ObservedObject var viewModel: MailIntegrationViewModel
    let webhookURL: String
    let apiKey: String
    let recipientEmail: String

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
        .alert("Export Failed", isPresented: Binding(get: {
            viewModel.exportErrorMessage != nil
        }, set: { newValue in
            if !newValue {
                viewModel.clearExportState()
            }
        })) {
            Button("OK", role: .cancel) {
                viewModel.clearExportState()
            }
        } message: {
            Text(viewModel.exportErrorMessage ?? "")
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
            List {
                if viewModel.exportResult != nil {
                    Section {
                        Label {
                            Text("Please check your emails.")
                                .font(.headline)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .symbolRenderingMode(.hierarchical)
                    }
                }

                ForEach(viewModel.spreadsheets, id: \.id) { spreadsheet in
                    Button {
                        Task {
                            await viewModel.export(spreadsheet: spreadsheet,
                                                   webhookURL: webhookURL,
                                                   apiKey: apiKey,
                                                   recipientEmail: recipientEmail)
                        }
                    } label: {
                        GoogleSpreadsheetRow(spreadsheet: spreadsheet)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isExporting)
                }
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
            Text(spreadsheet.ownerEmail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(spreadsheet.dateCreated.formatted(.dateTime.year().month().day().hour().minute()))
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Text(spreadsheet.url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    MailIntegrationSheet(viewModel: MailIntegrationViewModel(),
                         webhookURL: "https://example.com",
                         apiKey: "test",
                         recipientEmail: "preview@example.com")
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
