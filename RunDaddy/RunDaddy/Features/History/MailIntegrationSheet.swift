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
    @State private var navigationPath: [GoogleSpreadsheet] = []
    @State private var previousNavigationPath: [GoogleSpreadsheet] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationTitle("Google Sheets")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task {
                                await viewModel.refresh(webhookURL: webhookURL, apiKey: apiKey)
                            }
                        } label: {
                            Image(systemName: "repeat")
                        }
                        .disabled(viewModel.isLoading)
                    }
                }
                .task {
                    await viewModel.refresh(webhookURL: webhookURL, apiKey: apiKey)
                }
                .navigationDestination(for: GoogleSpreadsheet.self) { spreadsheet in
                    MailIntegrationSendView(viewModel: viewModel,
                                            spreadsheet: spreadsheet,
                                            webhookURL: webhookURL,
                                            apiKey: apiKey,
                                            recipientEmail: recipientEmail)
                }
        }
        .interactiveDismissDisabled(viewModel.isExporting)
        .onAppear {
            previousNavigationPath = navigationPath
        }
        .onChange(of: navigationPath) { _, newValue in
            guard viewModel.isExporting else {
                previousNavigationPath = newValue
                return
            }

            guard newValue.count >= previousNavigationPath.count else {
                DispatchQueue.main.async {
                    navigationPath = previousNavigationPath
                }
                return
            }

            previousNavigationPath = newValue
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
                NavigationLink(value: spreadsheet) {
                    GoogleSpreadsheetRow(spreadsheet: spreadsheet)
                        .padding(.vertical, 8)
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

private struct MailIntegrationSendView: View {
    @ObservedObject var viewModel: MailIntegrationViewModel
    let spreadsheet: GoogleSpreadsheet
    let webhookURL: String
    let apiKey: String
    let recipientEmail: String

    @Environment(\.dismiss) private var dismiss
    @State private var didStartSending = false

    var body: some View {
        VStack(spacing: 28) {
            if let export = viewModel.exportResult,
               export.spreadsheet.id == spreadsheet.id && !viewModel.isExporting {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)

                Text("Please check your emails.")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("We sent \(spreadsheet.name) to \(export.recipient).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if let error = viewModel.exportErrorMessage, !error.isEmpty, !viewModel.isExporting {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)

                Text(error)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    Task {
                        await sendExport()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)

                Text("Sending email…")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(spreadsheet.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .disabled(viewModel.isExporting)
            }
        }
        .task {
            guard !didStartSending else { return }
            didStartSending = true
            await sendExport()
        }
        .onDisappear {
            viewModel.clearExportState()
        }
    }

    private func sendExport() async {
        await viewModel.export(spreadsheet: spreadsheet,
                               webhookURL: webhookURL,
                               apiKey: apiKey,
                               recipientEmail: recipientEmail)
    }
}

private extension GoogleSpreadsheet {
    static let preview = GoogleSpreadsheet(id: "sample-sheet-id",
                                           name: "RunDaddy - Buggy",
                                           url: URL(string: "https://docs.google.com/spreadsheets/d/1Ba9NSw1jozlcasd3OZ-9LaDFXOHEr98iSrS-tPRTK8w/edit")!,
                                           ownerEmail: "loganjanssen02@gmail.com",
                                           dateCreated: Date(timeIntervalSince1970: 1_756_934_108))
}
