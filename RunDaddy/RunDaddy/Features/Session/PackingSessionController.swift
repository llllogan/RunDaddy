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
    private var sessionObservation: AnyCancellable?

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
        sessionObservation = viewModel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
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

    func repeatActiveSession() {
        guard let viewModel = activeSession?.viewModel else { return }
        viewModel.repeatCurrent()
    }

    func advanceActiveSession() {
        guard let viewModel = activeSession?.viewModel else { return }
        if viewModel.isSessionComplete {
            endSession()
        } else {
            viewModel.stepForward()
        }
    }

    func endSession() {
        guard let session = activeSession else {
            isSheetPresented = false
            return
        }
        session.viewModel.stopSession()
        activeSession = nil
        sessionObservation = nil
        isSheetPresented = false
    }

    struct ActiveSession {
        let run: Run
        let viewModel: PackingSessionViewModel
    }
}
