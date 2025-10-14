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
            .disabled(viewModel.isSessionComplete || viewModel.currentItemDescriptor == nil)

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
            .disabled(viewModel.currentItemDescriptor == nil && !viewModel.isSessionComplete)
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

    init(run: Run) {
        self.run = run
        self.runCoils = run.runCoils.sorted { lhs, rhs in
            if lhs.packOrder == rhs.packOrder {
                return lhs.coil.machinePointer < rhs.coil.machinePointer
            }
            return lhs.packOrder < rhs.packOrder
        }
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-AU")) ?? SFSpeechRecognizer()
        super.init()
        synthesizer.delegate = self
    }

    var totalCount: Int {
        runCoils.count
    }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        if isSessionComplete { return 1 }
        return Double(currentIndex) / Double(totalCount)
    }

    var progressDescription: String {
        guard totalCount > 0 else { return "No items" }
        if isSessionComplete { return "All \(totalCount) items packed" }
        return "Item \(min(currentIndex + 1, totalCount)) of \(totalCount)"
    }

    var currentRunCoil: RunCoil? {
        guard currentIndex < runCoils.count else { return nil }
        return runCoils[currentIndex]
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
        isSpeechInProgress = false
        errorMessage = nil
        guard !runCoils.isEmpty else {
            shouldResumeRecognitionAfterSpeech = false
            isSpeechInProgress = false
            isSessionComplete = true
            errorMessage = "This run has no items to pack."
            return
        }
        requestPermissions()
        commandHandledForCurrentItem = false
        if currentRunCoil != nil {
            speakCurrentItem()
        }
    }

    func stopSession() {
        shouldResumeRecognitionAfterSpeech = false
        isSpeechInProgress = false
        cancelRecognition()
        synthesizer.stopSpeaking(at: .immediate)
    }

    func advanceManually() {
        if isSessionComplete {
            stopSession()
        } else {
            shouldResumeRecognitionAfterSpeech = false
            synthesizer.stopSpeaking(at: .immediate)
            advanceToNextItem()
        }
    }

    func repeatCurrent() {
        shouldResumeRecognitionAfterSpeech = false
        synthesizer.stopSpeaking(at: .immediate)
        commandHandledForCurrentItem = false
        speakCurrentItem()
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
                            if !(self.synthesizer.isSpeaking) {
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
        isSpeechInProgress = false

        try configureAudioSessionIfNeeded()
        try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        audioTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!, resultHandler: { [weak self] result, error in
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
                    if !Self.benignSpeechErrors.contains(signature) {
                        self.errorMessage = error.localizedDescription
                    } else if self.errorMessage == error.localizedDescription {
                        self.errorMessage = nil
                    }
                    if self.shouldResumeRecognitionAfterSpeech && !self.isSpeechInProgress {
                        self.restartRecognition()
                    }
                }
            }
        })
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
        guard !commandHandledForCurrentItem else { return }
        commandHandledForCurrentItem = true
        advanceToNextItem()
    }

    private func advanceToNextItem() {
        guard let current = currentRunCoil else {
            completeSession()
            return
        }

        if !current.packed {
            current.packed = true
        }

        currentIndex += 1

        if currentIndex < runCoils.count {
            commandHandledForCurrentItem = false
            shouldResumeRecognitionAfterSpeech = true
            speakCurrentItem()
        } else {
            completeSession()
        }
    }

    private func speakCurrentItem() {
        guard let current = currentRunCoil else { return }
        shouldResumeRecognitionAfterSpeech = false
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
        shouldResumeRecognitionAfterSpeech = true
        let item = current.coil.item
        let machine = current.coil.machine.name
        let utterance = AVSpeechUtterance(string: "Next item. \(item.name). Machine \(machine). Need \(current.pick).")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    private func completeSession() {
        isSessionComplete = true
        shouldResumeRecognitionAfterSpeech = false
        cancelRecognition()
        isSpeechInProgress = true
        errorMessage = nil
        let utterance = AVSpeechUtterance(string: "Packing session complete. Great job.")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
        synthesizer.speak(utterance)
    }

    private func restartRecognition() {
        guard shouldResumeRecognitionAfterSpeech,
              !isSpeechInProgress,
              !isSessionComplete,
              !runCoils.isEmpty,
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

@MainActor
extension PackingSessionViewModel: @preconcurrency AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeechInProgress = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeechInProgress = false
        guard shouldResumeRecognitionAfterSpeech, !isSessionComplete else { return }
        restartRecognition()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeechInProgress = false
        guard shouldResumeRecognitionAfterSpeech, !isSessionComplete else { return }
        restartRecognition()
    }
}
