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
    @Environment(\.haptics) private var haptics
    @State private var navigationPath: [GoogleSpreadsheet] = []
    @State private var previousNavigationPath: [GoogleSpreadsheet] = []

    private var groupedSpreadsheets: [(date: Date, items: [GoogleSpreadsheet])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: viewModel.spreadsheets) { spreadsheet in
            calendar.startOfDay(for: spreadsheet.dateCreated)
        }

        return grouped
            .map { date, items in
                (date: date, items: items.sorted(by: { $0.dateCreated > $1.dateCreated }))
            }
            .sorted(by: { $0.date > $1.date })
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationTitle("Run Spreadsheets")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            haptics.secondaryButtonTap()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            haptics.secondaryButtonTap()
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
                                            recipientEmail: recipientEmail,
                                            onClose: { dismiss() })
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
                    haptics.secondaryButtonTap()
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
                ForEach(groupedSpreadsheets, id: \.date) { section in
                    Section(section.date.formatted(.dateTime.year().month().day())) {
                        ForEach(section.items, id: \.id) { spreadsheet in
                            NavigationLink(value: spreadsheet) {
                                GoogleSpreadsheetRow(spreadsheet: spreadsheet)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

private struct GoogleSpreadsheetRow: View {
    let spreadsheet: GoogleSpreadsheet

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(spreadsheet.name)
                .font(.headline)
            Text("Owner: \(spreadsheet.ownerEmail)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
private struct PreviewGoogleSheetsService: GoogleSheetsServicing {
    var spreadsheets: [GoogleSpreadsheet] = GoogleSpreadsheet.previewList

    func fetchSpreadsheets(webhookURLString: String, apiKey: String) async throws -> [GoogleSpreadsheet] {
        spreadsheets
    }

    func exportSpreadsheet(webhookURLString: String,
                           apiKey: String,
                           sheetID: String,
                           recipientEmail: String) async throws -> GoogleSpreadsheetExportResponse {
        GoogleSpreadsheetExportResponse(
            recipient: recipientEmail,
            spreadsheet: GoogleSpreadsheetExportSummary(id: sheetID,
                                                        name: "Mock Export",
                                                        url: URL(string: "https://example.com/mock")!,
                                                        tabCount: 3,
                                                        tabs: ["Summary", "Data", "Logs"],
                                                        archiveName: "MockExport.zip"),
            action: "export"
        )
    }
}

#Preview("Sheets With Sections") {
    MailIntegrationSheet(viewModel: MailIntegrationViewModel(sheetsService: PreviewGoogleSheetsService()),
                         webhookURL: "https://preview.run.daddy/webhook",
                         apiKey: "preview-key",
                         recipientEmail: "preview@example.com")
}

#Preview("Spreadsheet Row") {
    List {
        GoogleSpreadsheetRow(spreadsheet: .preview)
    }
    .listStyle(.insetGrouped)
}
#endif

private struct MailIntegrationSendView: View {
    @ObservedObject var viewModel: MailIntegrationViewModel
    let spreadsheet: GoogleSpreadsheet
    let webhookURL: String
    let apiKey: String
    let recipientEmail: String
    let onClose: () -> Void

    @State private var didStartSending = false
    @Environment(\.haptics) private var haptics

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
                    haptics.prominentActionTap()
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
                    haptics.secondaryButtonTap()
                    onClose()
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

    static var previewList: [GoogleSpreadsheet] {
        let now = Date()
        let calendar = Calendar.current
        let sixHoursAgo = calendar.date(byAdding: .hour, value: -6, to: now) ?? now.addingTimeInterval(-21_600)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        let yesterdayEvening = calendar.date(byAdding: .hour, value: -12, to: yesterday) ?? yesterday.addingTimeInterval(-43_200)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now) ?? now.addingTimeInterval(-172_800)

        return [
            GoogleSpreadsheet(id: "weekly-metrics",
                              name: "Weekly Metrics",
                              url: URL(string: "https://docs.google.com/spreadsheets/d/weekly-metrics")!,
                              ownerEmail: "ops@example.com",
                              dateCreated: now),
            GoogleSpreadsheet(id: "shift-log",
                              name: "Operator Shift Log",
                              url: URL(string: "https://docs.google.com/spreadsheets/d/shift-log")!,
                              ownerEmail: "team@example.com",
                              dateCreated: sixHoursAgo),
            GoogleSpreadsheet(id: "maintenance-check",
                              name: "Maintenance Checklist",
                              url: URL(string: "https://docs.google.com/spreadsheets/d/maintenance-check")!,
                              ownerEmail: "maintenance@example.com",
                              dateCreated: yesterday),
            GoogleSpreadsheet(id: "production-archive",
                              name: "Production Archive",
                              url: URL(string: "https://docs.google.com/spreadsheets/d/production-archive")!,
                              ownerEmail: "archive@example.com",
                              dateCreated: yesterdayEvening),
            GoogleSpreadsheet(id: "legacy-records",
                              name: "Legacy Records",
                              url: URL(string: "https://docs.google.com/spreadsheets/d/legacy-records")!,
                              ownerEmail: "records@example.com",
                              dateCreated: twoDaysAgo)
        ]
    }
}
