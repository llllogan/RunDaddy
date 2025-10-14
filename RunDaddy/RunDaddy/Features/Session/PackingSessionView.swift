//
//  PackingSessionView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import AVFoundation
import AVFAudio
import Combine
import Speech
import SwiftData
import SwiftUI

struct PackingSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PackingSessionViewModel

    init(run: Run) {
        _viewModel = StateObject(wrappedValue: PackingSessionViewModel(run: run))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)

                Text(viewModel.progressDescription)
                    .font(.headline)

                SessionContentView(viewModel: viewModel)

                ControlBar(viewModel: viewModel) {
                    viewModel.stopSession()
                    dismiss()
                }

                if !viewModel.lastHeardPhrase.isEmpty {
                    Label("Heard: \(viewModel.lastHeardPhrase)", systemImage: "waveform")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Packing Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        viewModel.stopSession()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }
}

private struct SessionContentView: View {
    @ObservedObject var viewModel: PackingSessionViewModel

    var body: some View {
        Group {
            if viewModel.isSessionComplete {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("All items packed")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if let machine = viewModel.currentMachineDescriptor {
                VStack(alignment: .leading, spacing: 12) {
                    Text(machine.name)
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)

                    if let location = machine.location {
                        Text(location)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    Text("Get ready to pack this machine.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if let descriptor = viewModel.currentItemDescriptor {
                VStack(alignment: .leading, spacing: 12) {
                    Text(descriptor.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)

                    Text(descriptor.subtitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 16) {
                        SessionLabeledValue(title: "Machine", value: descriptor.machine)
                        SessionLabeledValue(title: "Need", value: "\(descriptor.pick)")
                        SessionLabeledValue(title: "Pointer", value: "\(descriptor.pointer)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ProgressView("Preparing session…")
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct ControlBar: View {
    @ObservedObject var viewModel: PackingSessionViewModel
    let finishAction: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.repeatCurrent()
            } label: {
                Label("Repeat", systemImage: "arrow.uturn.left")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isSessionComplete || !viewModel.hasActiveStep)

            Button {
                if viewModel.isSessionComplete {
                    finishAction()
                } else {
                    viewModel.advanceManually()
                }
            } label: {
                Label(viewModel.isSessionComplete ? "Finish" : "Next",
                      systemImage: viewModel.isSessionComplete ? "checkmark.circle" : "forward.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isSessionComplete ? .green : .accentColor)
            .disabled(!viewModel.isSessionComplete && !viewModel.hasActiveStep)
        }
    }
}


@MainActor
final class PackingSessionViewModel: NSObject, ObservableObject {
    @Published var currentIndex: Int = 0
    @Published var isListening: Bool = false
    @Published var errorMessage: String?
    @Published var lastHeardPhrase: String = ""
    @Published var isSessionComplete: Bool = false

    let run: Run
    private let runCoils: [RunCoil]
    private let steps: [SessionStep]
    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer?
    private var audioSessionConfigured = false

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioTapInstalled = false
    private var commandHandledForCurrentItem = false
    private var sessionStarted = false
    private var shouldResumeRecognitionAfterSpeech = true
    private var isSpeechInProgress = false
    private var shouldAutoAdvanceAfterSpeech = false

    private static let cancellationDomain = "kLSRErrorDomain"
    private static let cancellationCode = 301
    private static let assistantDomain = "kAFAssistantErrorDomain"
    private static let benignSpeechErrors: Set<SpeechErrorSignature> = [
        SpeechErrorSignature(domain: cancellationDomain, code: cancellationCode),
        SpeechErrorSignature(domain: assistantDomain, code: 1100),
        SpeechErrorSignature(domain: assistantDomain, code: 1101),
        SpeechErrorSignature(domain: assistantDomain, code: 1107),
        SpeechErrorSignature(domain: assistantDomain, code: 1110)
    ]

    private enum SessionStep {
        case machine(Machine)
        case runCoil(RunCoil)

        var isRunCoil: Bool {
            if case .runCoil = self {
                return true
            }
            return false
        }
    }

    init(run: Run) {
        self.run = run
        let machineOrder = Self.machineOrder(for: Array(run.runCoils))
        let filtered = run.runCoils
            .filter { $0.pick > 0 }
            .sorted { lhs, rhs in
                if lhs.packOrder != rhs.packOrder {
                    return lhs.packOrder < rhs.packOrder
                }
                let lhsOrder = machineOrder[lhs.coil.machine.id] ?? Int.max
                let rhsOrder = machineOrder[rhs.coil.machine.id] ?? Int.max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.coil.machinePointer < rhs.coil.machinePointer
            }
        self.runCoils = filtered
        self.steps = PackingSessionViewModel.buildSteps(from: filtered)
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-AU")) ?? SFSpeechRecognizer()
        super.init()
        synthesizer.delegate = self
    }

    var hasActiveStep: Bool {
        currentStep != nil
    }

    var progress: Double {
        guard totalItemCount > 0 else { return 0 }
        if isSessionComplete { return 1 }
        return Double(completedItemCount) / Double(totalItemCount)
    }

    var progressDescription: String {
        guard totalItemCount > 0 else { return "No items" }
        if isSessionComplete { return "All \(totalItemCount) items packed" }
        if let machine = currentMachineDescriptor {
            return "Machine \(machine.name)"
        }
        let nextIndex = completedItemCount + 1
        return "Item \(min(nextIndex, totalItemCount)) of \(totalItemCount)"
    }

    fileprivate var currentMachineDescriptor: MachineDescriptor? {
        guard let step = currentStep else { return nil }
        switch step {
        case .machine(let machine):
            let location = machine.locationLabel ?? machine.location?.name
            return MachineDescriptor(name: machine.name, location: location)
        case .runCoil:
            return nil
        }
    }

    fileprivate var currentItemDescriptor: CoilDescriptor? {
        guard let runCoil = currentRunCoil else { return nil }
        let coil = runCoil.coil
        let item = coil.item
        return CoilDescriptor(title: item.name,
                              subtitle: item.type.isEmpty ? item.id : "\(item.type) • \(item.id)",
                              machine: coil.machine.name,
                              pick: runCoil.pick,
                              pointer: coil.machinePointer)
    }

    func startSession() {
        guard !sessionStarted else { return }
        sessionStarted = true
        shouldResumeRecognitionAfterSpeech = true
        shouldAutoAdvanceAfterSpeech = false
        isSpeechInProgress = false
        isSessionComplete = false
        errorMessage = nil

        guard !steps.isEmpty else {
            shouldResumeRecognitionAfterSpeech = false
            isSpeechInProgress = false
            isSessionComplete = true
            errorMessage = "This run has no items to pack."
            return
        }

        requestPermissions()
        commandHandledForCurrentItem = false
        speakCurrentStep()
    }

    func stopSession() {
        shouldResumeRecognitionAfterSpeech = false
        shouldAutoAdvanceAfterSpeech = false
        isSpeechInProgress = false
        cancelRecognition()
        synthesizer.stopSpeaking(at: .immediate)
    }

    func advanceManually() {
        if isSessionComplete {
            stopSession()
        } else {
            shouldResumeRecognitionAfterSpeech = false
            shouldAutoAdvanceAfterSpeech = false
            synthesizer.stopSpeaking(at: .immediate)
            advanceToNextStep()
        }
    }

    func repeatCurrent() {
        guard hasActiveStep else { return }
        shouldResumeRecognitionAfterSpeech = false
        shouldAutoAdvanceAfterSpeech = false
        synthesizer.stopSpeaking(at: .immediate)
        commandHandledForCurrentItem = false
        speakCurrentStep()
    }

    private var currentStep: SessionStep? {
        guard currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    private var currentRunCoil: RunCoil? {
        guard let step = currentStep else { return nil }
        if case .runCoil(let runCoil) = step {
            return runCoil
        }
        return nil
    }

    private var totalItemCount: Int {
        runCoils.count
    }

    private var completedItemCount: Int {
        guard currentIndex > 0 else { return 0 }
        return steps.prefix(min(currentIndex, steps.count)).reduce(0) { count, step in
            count + (step.isRunCoil ? 1 : 0)
        }
    }

    private static func machineOrder(for runCoils: [RunCoil]) -> [String: Int] {
        let sorted = runCoils.sorted { lhs, rhs in
            if lhs.packOrder != rhs.packOrder {
                return lhs.packOrder < rhs.packOrder
            }
            return lhs.coil.machinePointer < rhs.coil.machinePointer
        }
        var order: [String: Int] = [:]
        for (index, runCoil) in sorted.enumerated() {
            let machineID = runCoil.coil.machine.id
            if order[machineID] == nil {
                order[machineID] = index
            }
        }
        return order
    }

    private static func buildSteps(from runCoils: [RunCoil]) -> [SessionStep] {
        var steps: [SessionStep] = []
        var lastMachineID: String?
        for runCoil in runCoils {
            let machine = runCoil.coil.machine
            if lastMachineID != machine.id {
                steps.append(.machine(machine))
                lastMachineID = machine.id
            }
            steps.append(.runCoil(runCoil))
        }
        return steps
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult) {
        let transcript = result.bestTranscription.formattedString.lowercased()
        lastHeardPhrase = transcript

        if transcript.contains("next item") {
            handleNextCommand()
        } else if transcript.contains("repeat item") {
            repeatCurrent()
        }

        if result.isFinal && shouldResumeRecognitionAfterSpeech && !isSpeechInProgress {
            restartRecognition()
        }
    }

    private func handleNextCommand() {
        guard !isSessionComplete else { return }
        if case .runCoil = currentStep {
            guard !commandHandledForCurrentItem else { return }
            commandHandledForCurrentItem = true
        }
        advanceToNextStep()
    }

    private func advanceToNextStep() {
        guard !isSessionComplete else { return }
        if let step = currentStep, case let .runCoil(runCoil) = step, !runCoil.packed {
            runCoil.packed = true
        }

        currentIndex += 1
        commandHandledForCurrentItem = false
        shouldAutoAdvanceAfterSpeech = false

        if currentIndex < steps.count {
            speakCurrentStep()
        } else {
            completeSession()
        }
    }

    private func speakCurrentStep() {
        guard let step = currentStep else { return }

        shouldResumeRecognitionAfterSpeech = false
        shouldAutoAdvanceAfterSpeech = false
        cancelRecognition()
        errorMessage = nil

        do {
            try configureAudioSessionIfNeeded()
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = error.localizedDescription
        }

        commandHandledForCurrentItem = false
        isSpeechInProgress = true

        switch step {
        case .machine(let machine):
            shouldAutoAdvanceAfterSpeech = true
            let utterance = AVSpeechUtterance(string: "Machine \(machine.name).")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            synthesizer.speak(utterance)
        case .runCoil(let runCoil):
            shouldResumeRecognitionAfterSpeech = true
            let item = runCoil.coil.item
            let need = max(runCoil.pick, 0)
            let needPhrase = need == 1 ? "Need one." : "Need \(need)."
            let utterance = AVSpeechUtterance(string: "\(item.name). \(needPhrase)")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            synthesizer.speak(utterance)
        }
    }

    private func requestPermissions() {
        let recordPermissionHandler: @Sendable (Bool) -> Void = { granted in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !granted {
                    self.shouldResumeRecognitionAfterSpeech = false
                    self.errorMessage = "Microphone access is required for packing sessions."
                    return
                }

                SFSpeechRecognizer.requestAuthorization { status in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        switch status {
                        case .authorized:
                            if !self.synthesizer.isSpeaking {
                                self.restartRecognition()
                            }
                        case .denied:
                            self.errorMessage = "Speech recognition access denied."
                        case .restricted:
                            self.errorMessage = "Speech recognition is restricted on this device."
                        case .notDetermined:
                            self.errorMessage = "Speech recognition permission not determined."
                        @unknown default:
                            self.errorMessage = "Unknown speech recognition authorization state."
                        }
                    }
                }
            }
        }

        if #available(iOS 17, *) {
            AVAudioApplication.requestRecordPermission { granted in
                recordPermissionHandler(granted)
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(recordPermissionHandler)
        }
    }

    private func startListening() throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer is unavailable."
            return
        }

        cancelRecognition()
        shouldAutoAdvanceAfterSpeech = false
        isSpeechInProgress = false

        try configureAudioSessionIfNeeded()
        try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        audioTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        recognitionTask = speechRecognizer.recognitionTask(with: request, resultHandler: { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                Task { @MainActor [weak self] in
                    self?.handleRecognitionResult(result)
                }
            }
            if let error = error as NSError? {
                Task { @MainActor in
                    guard !self.isSpeechInProgress else { return }
                    let signature = SpeechErrorSignature(domain: error.domain, code: error.code)
                    if Self.benignSpeechErrors.contains(signature) {
                        self.errorMessage = nil
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                    if self.shouldResumeRecognitionAfterSpeech && !self.isSpeechInProgress {
                        self.restartRecognition()
                    }
                }
            }
        })
    }

    private func restartRecognition() {
        guard shouldResumeRecognitionAfterSpeech,
              !shouldAutoAdvanceAfterSpeech,
              !isSpeechInProgress,
              !isSessionComplete,
              totalItemCount > 0,
              isMicrophoneAuthorized,
              isSpeechAuthorized else {
            if isListening {
                cancelRecognition()
            }
            return
        }

        do {
            try startListening()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if audioTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioTapInstalled = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
        isSpeechInProgress = false
        lastHeardPhrase = ""
    }

    private var isMicrophoneAuthorized: Bool {
        if #available(iOS 17, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        } else {
            return AVAudioSession.sharedInstance().recordPermission == .granted
        }
    }

    private var isSpeechAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    private func configureAudioSessionIfNeeded() throws {
        guard !audioSessionConfigured else { return }
        let audioSession = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.duckOthers, .defaultToSpeaker]
        if #available(iOS 13.0, *) {
            options.insert(.allowBluetoothHFP)
            options.insert(.allowBluetoothA2DP)
        }
        try audioSession.setCategory(.playAndRecord,
                                     mode: .spokenAudio,
                                     options: options)
        audioSessionConfigured = true
    }

    private func completeSession() {
        isSessionComplete = true
        currentIndex = steps.count
        shouldResumeRecognitionAfterSpeech = false
        shouldAutoAdvanceAfterSpeech = false
        cancelRecognition()
        isSpeechInProgress = true
        errorMessage = nil
        let utterance = AVSpeechUtterance(string: "Packing session complete. Great job.")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
        synthesizer.speak(utterance)
    }
}

private struct MachineDescriptor {
    let name: String
    let location: String?
}

private struct CoilDescriptor {
    let title: String
    let subtitle: String
    let machine: String
    let pick: Int64
    let pointer: Int64
}

private struct SpeechErrorSignature: Hashable {
    let domain: String
    let code: Int
}

private struct SessionLabeledValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

extension PackingSessionViewModel: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeechInProgress = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeechInProgress = false
            if self.shouldAutoAdvanceAfterSpeech {
                self.shouldAutoAdvanceAfterSpeech = false
                self.advanceToNextStep()
                return
            }
            guard self.shouldResumeRecognitionAfterSpeech, !self.isSessionComplete else { return }
            self.restartRecognition()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeechInProgress = false
            if self.shouldAutoAdvanceAfterSpeech {
                self.shouldAutoAdvanceAfterSpeech = false
                self.advanceToNextStep()
                return
            }
            guard self.shouldResumeRecognitionAfterSpeech, !self.isSessionComplete else { return }
            self.restartRecognition()
        }
    }
}
