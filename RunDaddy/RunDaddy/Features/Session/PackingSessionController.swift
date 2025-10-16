//
//  PackingSessionController.swift
//  RunDaddy
//
//  Created by Logan Janssen on 02/03/2026.
//

import Combine
import SwiftUI

@MainActor
final class PackingSessionController: ObservableObject {
    @Published private(set) var activeSession: ActiveSession?
    @Published var isSheetPresented: Bool = false

    var activeViewModel: PackingSessionViewModel? {
        activeSession?.viewModel
    }

    var hasActiveSession: Bool {
        activeSession != nil
    }

    func beginSession(for run: Run) {
        if let session = activeSession {
            if session.run.id == run.id {
                isSheetPresented = true
                return
            } else {
                endSession()
            }
        }

        let viewModel = PackingSessionViewModel(run: run)
        activeSession = ActiveSession(run: run, viewModel: viewModel)
        isSheetPresented = true
        viewModel.startSession()
    }

    func minimizeSession() {
        guard hasActiveSession else { return }
        isSheetPresented = false
    }

    func expandSession() {
        guard hasActiveSession else { return }
        isSheetPresented = true
    }

    func endSession() {
        guard let session = activeSession else {
            isSheetPresented = false
            return
        }
        session.viewModel.stopSession()
        activeSession = nil
        isSheetPresented = false
    }

    struct ActiveSession {
        let run: Run
        let viewModel: PackingSessionViewModel
    }
}
