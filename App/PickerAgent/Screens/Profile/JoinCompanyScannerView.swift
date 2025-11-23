//
//  JoinCompanyScannerView.swift
//  PickAgent
//
//  Created by ChatGPT on 5/8/2025.
//

import SwiftUI

struct JoinCompanyScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = JoinCompanyViewModel(
        inviteCodesService: InviteCodesService(),
        authService: AuthService()
    )
    @State private var scannerResumeToken = UUID()

    var onJoined: (() -> Void)?

    var body: some View {
        ZStack {
            QRScannerView(
                onCodeFound: handleCodeFound,
                onCancel: { dismiss() },
                resumeToken: scannerResumeToken
            )
            .ignoresSafeArea()

            if viewModel.isJoining {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .overlay(
                        ProgressView("Joining company...")
                            .foregroundStyle(.white)
                            .padding()
                    )
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
                scannerResumeToken = UUID()
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: viewModel.didJoinCompany, initial: false) { _, didJoin in
            guard didJoin else { return }
            onJoined?()
            dismiss()
        }
    }

    private func handleCodeFound(_ code: String) {
        guard !viewModel.isJoining else { return }
        viewModel.joinWithQRCode(code)
    }
}

#Preview {
    JoinCompanyScannerView()
}
