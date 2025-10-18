//
//  PackingSessionView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import AVFoundation
import Foundation
import MediaPlayer
import SwiftData
import SwiftUI
import Combine

struct PackingSessionView: View {
    @Environment(\.dismiss) private var dismiss
    private let sessionController: PackingSessionController?
    @ObservedObject private var viewModel: PackingSessionViewModel

    init(run: Run, controller: PackingSessionController? = nil) {
        self.sessionController = controller
        _viewModel = ObservedObject(wrappedValue: PackingSessionViewModel(run: run))
    }

    init(viewModel: PackingSessionViewModel, controller: PackingSessionController? = nil) {
        self.sessionController = controller
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                SessionContentView(viewModel: viewModel)

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
                    Button {
                        if let sessionController {
                            sessionController.endSession()
                        } else {
                            viewModel.stopSession()
                        }
                        dismiss()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .labelStyle(.titleOnly)
                    }
                    .accessibilityLabel("Stop packing session")
                }
                if let sessionController {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            sessionController.minimizeSession()
                            dismiss()
                        } label: {
                            Label("Minimize", systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                        .accessibilityLabel("Minimize packing session")
                    }
                }
                
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        viewModel.stepBackward()
                    } label: {
                        Label("Previous", systemImage: "backward.fill")
                            .labelStyle(.titleOnly)
                    }
                    
                    Button {
                        viewModel.repeatCurrent()
                    } label: {
                        Label("Repeat", systemImage: "arrow.uturn.left")
                            .labelStyle(.titleOnly)
                    }
                    
                    Button {
                        if viewModel.isSessionComplete {
                            if let sessionController {
                                sessionController.endSession()
                            } else {
                                viewModel.stopSession()
                            }
                            dismiss()
                        } else {
                            viewModel.stepForward()
                        }
                    } label: {
                        Label(viewModel.isSessionComplete ? "Finish" : "Next",
                              systemImage: viewModel.isSessionComplete ? "checkmark.circle" : "forward.fill")
                        .labelStyle(.titleOnly)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isSessionComplete ? .green : .accentColor)
                    .disabled(!viewModel.isSessionComplete && !viewModel.hasActiveStep)
                }
            }
        }
        .onAppear {
#if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                viewModel.previewSelectFirstItem()
                return
            }
#endif
            viewModel.startSession()
        }
        .onDisappear {
            if sessionController == nil {
                viewModel.stopSession()
            }
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

                    Text("Use the buttons below or your headset controls to navigate.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if !viewModel.visibleItemDescriptors.isEmpty {
                SessionItemCarousel(items: viewModel.visibleItemDescriptors)
            } else if let descriptor = viewModel.currentItemDescriptor {
                SessionItemCard(descriptor: descriptor, position: .current)
            } else {
                ProgressView("Preparing session…")
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - View model

@MainActor
final class PackingSessionViewModel: NSObject, ObservableObject {
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isSessionComplete: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSpeechInProgress: Bool = false
    @Published private(set) var isSessionRunning: Bool = false
    @Published private(set) var currentRunCoilID: String?

    let run: Run
    private let runCoils: [RunCoil]
    private let steps: [SessionStep]
    private let synthesizer = AVSpeechSynthesizer()
    private lazy var sessionVoice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice.preferredSiriVoice(forLanguage: "en-AU")

    private var audioSessionConfigured = false
    private let silentLoop = SilentLoopPlayer()
    private var remoteCommandTokens: [RemoteCommandToken] = []
    private let commandCenter = MPRemoteCommandCenter.shared()

    init(run: Run) {
        self.run = run
        let machineOrder = Self.machineOrder(for: Array(run.runCoils))
        let filtered = run.runCoils
            .filter { $0.pick > 0 && !$0.packed }
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
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public surface

    var hasActiveStep: Bool {
        !isSessionComplete && currentStep != nil
    }

    var canStepBackward: Bool {
        isSessionComplete ? !steps.isEmpty : currentIndex > 0
    }

    var progress: Double {
        guard totalItemCount > 0 else { return 0 }
        if isSessionComplete { return 1 }
        return Double(packedItemCount) / Double(totalItemCount)
    }

    var progressDescription: String {
        guard totalItemCount > 0 else { return "No items" }
        if isSessionComplete { return "All \(totalItemCount) items packed" }
        if let machine = currentMachineDescriptor {
            return "Machine \(machine.name)"
        }
        let nextIndex = packedItemCount + 1
        return "Item \(min(nextIndex, totalItemCount)) of \(totalItemCount)"
    }

    var currentMachineDescriptor: MachineDescriptor? {
        guard let step = currentStep else { return nil }
        if case .machine(let machine) = step {
            return MachineDescriptor(name: machine.name, location: machine.locationLabel ?? machine.location?.name)
        }
        return nil
    }

    var currentItemDescriptor: CoilDescriptor? {
        guard let step = currentStep else { return nil }
        if case .runCoil(let runCoil) = step {
            return descriptor(for: runCoil)
        }
        return nil
    }

    var visibleItemDescriptors: [VisibleCoilDescriptor] {
        guard let index = currentRunCoilIndex,
              let current = descriptor(at: index) else { return [] }

        var descriptors: [VisibleCoilDescriptor] = []
        if let previous = descriptor(at: index - 1) {
            descriptors.append(VisibleCoilDescriptor(position: .previous, descriptor: previous))
        }
        descriptors.append(VisibleCoilDescriptor(position: .current, descriptor: current))
        if let next = descriptor(at: index + 1) {
            descriptors.append(VisibleCoilDescriptor(position: .next, descriptor: next))
        }
        return descriptors
    }

    func startSession() {
        guard !steps.isEmpty else {
            isSessionComplete = true
            if run.runCoils.contains(where: { $0.pick > 0 }) {
                errorMessage = "All items are already packed."
            } else {
                errorMessage = "This run has no items to pack."
            }
            return
        }

        errorMessage = nil
        guard !isSessionRunning else { return }
        configureAudioSessionIfNeeded()
        silentLoop.start()
        isSessionRunning = true
        refreshCurrentRunCoilMarker()
        configureRemoteCommandsIfNeeded()
        updateNowPlayingInfo()
        updatePlaybackState()
        speakCurrentStep()
    }

    func stopSession() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeechInProgress = false
        silentLoop.stop()
        isSessionRunning = false
        currentRunCoilID = nil
        tearDownRemoteCommands()
        deactivateAudioSession()
        updatePlaybackState()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func stepForward() {
        guard !isSessionComplete else { return }
        synthesizer.stopSpeaking(at: .immediate)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            advanceToNextStep()
        }
    }

    func stepBackward() {
        synthesizer.stopSpeaking(at: .immediate)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            moveToPreviousStep()
        }
    }

    func repeatCurrent() {
        synthesizer.stopSpeaking(at: .immediate)
        if isSessionComplete {
            announceCompletion()
        } else {
            speakCurrentStep()
        }
    }

    // MARK: - Step management

    private var currentStep: SessionStep? {
        guard currentIndex >= 0, currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    private var currentRunCoilIndex: Int? {
        guard let step = currentStep else { return nil }
        if case .runCoil(let runCoil) = step {
            return runCoils.firstIndex(where: { $0.id == runCoil.id })
        }
        return nil
    }

    private var totalItemCount: Int {
        runCoils.count
    }

    private var packedItemCount: Int {
        runCoils.filter(\.packed).count
    }

    private var activeRunCoil: RunCoil? {
        guard let step = currentStep, case let .runCoil(runCoil) = step else {
            return nil
        }
        return runCoil
    }

    private func descriptor(at index: Int) -> CoilDescriptor? {
        guard index >= 0, index < runCoils.count else { return nil }
        return descriptor(for: runCoils[index])
    }

    private func descriptor(for runCoil: RunCoil) -> CoilDescriptor {
        let coil = runCoil.coil
        let item = coil.item
        return CoilDescriptor(id: runCoil.id,
                              title: item.name,
                              subtitle: item.type.isEmpty ? item.id : "\(item.type) • \(item.id)",
                              machine: coil.machine.name,
                              pick: runCoil.pick,
                              pointer: coil.machinePointer)
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
            if order[runCoil.coil.machine.id] == nil {
                order[runCoil.coil.machine.id] = index
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

    private func advanceToNextStep() {
        if let step = currentStep, case let .runCoil(runCoil) = step {
            runCoil.packed = true
        }

        let nextIndex = currentIndex + 1
        if nextIndex >= steps.count {
            completeSession()
        } else {
            currentIndex = nextIndex
            updateNowPlayingInfo()
            speakCurrentStep()
            refreshCurrentRunCoilMarker()
        }
    }

    private func moveToPreviousStep() {
        if isSessionComplete {
            isSessionComplete = false
            currentIndex = max(steps.count - 1, 0)
        } else {
            guard currentIndex > 0 else { return }
            currentIndex -= 1
        }

        if let step = currentStep, case let .runCoil(runCoil) = step {
            runCoil.packed = false
        }

        updateNowPlayingInfo()
        speakCurrentStep()
        refreshCurrentRunCoilMarker()
    }

    // MARK: - Speech

    private func speakCurrentStep() {
        guard let step = currentStep else {
            announceCompletion()
            return
        }

        let utterance: AVSpeechUtterance
        switch step {
        case .machine(let machine):
            utterance = AVSpeechUtterance(string: "Machine \(machine.name).")
        case .runCoil(let runCoil):
            let item = runCoil.coil.item
            let need = max(runCoil.pick, 0)
            let needPhrase = need == 1 ? "Need one." : "Need \(need)."
            let typeText = item.type.trimmingCharacters(in: .whitespacesAndNewlines)
            var segments: [String] = ["\(item.name)."]
            if !typeText.isEmpty {
                segments.append("\(typeText).")
            }
            segments.append(needPhrase)
            utterance = AVSpeechUtterance(string: segments.joined(separator: " "))
        }

        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        if let sessionVoice {
            utterance.voice = sessionVoice
        }
        synthesizer.speak(utterance)
        updatePlaybackState()
    }

    private func announceCompletion() {
        let utterance = AVSpeechUtterance(string: "Packing session complete. Great job.")
        if let sessionVoice {
            utterance.voice = sessionVoice
        }
        synthesizer.speak(utterance)
        updatePlaybackState()
    }

    private func completeSession() {
        isSessionComplete = true
        currentIndex = steps.count
        refreshCurrentRunCoilMarker()
        updateNowPlayingInfoForCompletion()
        updatePlaybackState()
        announceCompletion()
    }

    // MARK: - Audio session & media remote

    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback,
                                         mode: .spokenAudio,
                                         options: [.duckOthers,
                                                   .interruptSpokenAudioAndMixWithOthers,
                                                   .allowBluetooth,
                                                   .allowBluetoothA2DP,
                                                   .allowAirPlay])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            audioSessionConfigured = true
            if errorMessage != nil {
                errorMessage = nil
            }
        } catch {
            if !error.shouldSuppressForAudioSession {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deactivateAudioSession() {
        guard audioSessionConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // keep the last shown error if any
        }
        audioSessionConfigured = false
    }

    private func configureRemoteCommandsIfNeeded() {
        guard remoteCommandTokens.isEmpty else { return }

        let nextToken = commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !self.isSessionComplete {
                self.stepForward()
            }
            return .success
        }

        let previousToken = commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.repeatCurrent()
            return .success
        }

        let playToken = commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.repeatCurrent()
            return .success
        }

        let pauseToken = commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.synthesizer.stopSpeaking(at: .immediate)
            self.updatePlaybackState()
            return .success
        }

        let toggleToken = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isSpeechInProgress {
                self.synthesizer.stopSpeaking(at: .immediate)
                self.updatePlaybackState()
            } else {
                self.repeatCurrent()
            }
            return .success
        }

        remoteCommandTokens = [
            RemoteCommandToken(command: commandCenter.nextTrackCommand, token: nextToken),
            RemoteCommandToken(command: commandCenter.previousTrackCommand, token: previousToken),
            RemoteCommandToken(command: commandCenter.playCommand, token: playToken),
            RemoteCommandToken(command: commandCenter.pauseCommand, token: pauseToken),
            RemoteCommandToken(command: commandCenter.togglePlayPauseCommand, token: toggleToken)
        ]

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        updatePlaybackState()
    }

    private func tearDownRemoteCommands() {
        guard !remoteCommandTokens.isEmpty else { return }
        remoteCommandTokens.forEach { token in
            token.command.removeTarget(token.token)
        }
        remoteCommandTokens.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [:]
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyPlaybackRate] = isSessionRunning ? 1 : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = silentLoop.currentTime
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = steps.count
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = min(currentIndex, max(steps.count - 1, 0))

        if let descriptor = currentItemDescriptor {
            info[MPMediaItemPropertyTitle] = descriptor.title
            info[MPMediaItemPropertyArtist] = descriptor.machine
        } else if let machine = currentMachineDescriptor {
            info[MPMediaItemPropertyTitle] = machine.name
            info[MPMediaItemPropertyArtist] = machine.location ?? "Packing"
        } else {
            info[MPMediaItemPropertyTitle] = "Packing Session"
            info[MPMediaItemPropertyArtist] = runDisplayTitle
        }

        info[MPMediaItemPropertyAlbumTitle] = runDisplayTitle
        info[MPMediaItemPropertyPlaybackDuration] = 3600

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingInfoForCompletion() {
        var info: [String: Any] = [:]
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyPlaybackRate] = isSessionRunning ? 1 : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = silentLoop.currentTime
        info[MPMediaItemPropertyTitle] = "Session Complete"
        info[MPMediaItemPropertyArtist] = runDisplayTitle
        info[MPMediaItemPropertyAlbumTitle] = runDisplayTitle
        info[MPMediaItemPropertyPlaybackDuration] = 3600
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updatePlaybackState() {
        MPNowPlayingInfoCenter.default().playbackState = isSessionRunning ? .playing : .paused
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isSessionRunning ? 1 : 0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = silentLoop.currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private var runDisplayTitle: String {
        run.runner
    }

    private func refreshCurrentRunCoilMarker() {
        guard !isSessionComplete else {
            currentRunCoilID = nil
            return
        }
        currentRunCoilID = activeRunCoil?.id
    }
}

// MARK: - Speech synthesizer delegate

extension PackingSessionViewModel: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            isSpeechInProgress = true
            updateNowPlayingInfo()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            isSpeechInProgress = false
            updateNowPlayingInfo()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            isSpeechInProgress = false
            updateNowPlayingInfo()
        }
    }
}

// MARK: - Supporting types

private struct SessionItemCarousel: View {
    let items: [VisibleCoilDescriptor]
    private let spacing: CGFloat = 12
    @State private var cardHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .center) {
            ForEach(items, id: \.descriptor.id) { item in
                SessionItemCard(descriptor: item.descriptor, position: item.position)
                    .offset(y: offset(for: item.position))
                    .zIndex(zIndex(for: item.position))
                    .transition(transition(for: item.position))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: carouselHeight)
        .onPreferenceChange(SessionItemHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            if abs(height - cardHeight) > 0.5 {
                cardHeight = height
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.82), value: items)
        .animation(.spring(response: 0.6, dampingFraction: 0.82), value: cardHeight)
    }

    private var carouselHeight: CGFloat {
        guard cardHeight > 0 else { return 320 }
        switch items.count {
        case 3:
            return cardHeight * 3 + spacing * 2
        case 2:
            return cardHeight * 2 + spacing
        default:
            return cardHeight
        }
    }

    private func offset(for position: VisibleCoilDescriptor.Position) -> CGFloat {
        guard cardHeight > 0 else { return fallbackOffset(for: position) }
        let step = cardHeight + spacing
        switch position {
        case .previous:
            return -step
        case .current:
            return 0
        case .next:
            return step
        }
    }

    private func fallbackOffset(for position: VisibleCoilDescriptor.Position) -> CGFloat {
        switch position {
        case .previous:
            return -220
        case .current:
            return 0
        case .next:
            return 220
        }
    }

    private func zIndex(for position: VisibleCoilDescriptor.Position) -> Double {
        switch position {
        case .current:
            return 3
        case .next:
            return 2
        case .previous:
            return 1
        }
    }

    private func transition(for position: VisibleCoilDescriptor.Position) -> AnyTransition {
        switch position {
        case .previous:
            return .move(edge: .top).combined(with: .opacity)
        case .current:
            return .opacity
        case .next:
            return .move(edge: .bottom).combined(with: .opacity)
        }
    }
}

private struct SessionItemCard: View {
    let descriptor: CoilDescriptor
    let position: VisibleCoilDescriptor.Position

    private var isCurrent: Bool {
        position == .current
    }

    var body: some View {
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
                SessionLabeledValue(title: "Coil", value: "\(descriptor.pointer)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(isCurrent ? 1 : 0.45)
        .scaleEffect(isCurrent ? 1 : 0.98)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SessionItemHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .animation(.easeInOut(duration: 0.2), value: isCurrent)
        .accessibilityHidden(!isCurrent)
        .allowsHitTesting(false)
    }
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

struct MachineDescriptor {
    let name: String
    let location: String?
}

struct CoilDescriptor: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let machine: String
    let pick: Int64
    let pointer: Int64
}

struct VisibleCoilDescriptor: Identifiable, Equatable {
    enum Position: String {
        case previous
        case current
        case next
    }

    let position: Position
    let descriptor: CoilDescriptor

    var id: String {
        descriptor.id
    }
}

private struct SessionItemHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private final class SilentLoopPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let buffer: AVAudioPCMBuffer
    private(set) var isRunning = false

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            fatalError("Unable to create audio format for silent loop")
        }
        self.format = format
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else {
            fatalError("Unable to allocate silent audio buffer")
        }
        buffer.frameLength = buffer.frameCapacity
        self.buffer = buffer

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.volume = 0
        engine.prepare()
    }

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }
        do {
            try engine.start()
        } catch {
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        player.play()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        player.stop()
        player.reset()
        engine.stop()
        engine.reset()
        isRunning = false
    }

    var currentTime: TimeInterval {
        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return 0 }
        return TimeInterval(playerTime.sampleTime) / format.sampleRate
    }
}

private struct RemoteCommandToken {
    let command: MPRemoteCommand
    let token: Any
}

private enum SessionStep {
    case machine(Machine)
    case runCoil(RunCoil)
}

#if DEBUG
private struct PackingSessionPreviewContainer: View {
    @StateObject private var viewModel = PackingSessionViewModel(run: PreviewFixtures.sampleRun)

    var body: some View {
        PackingSessionView(viewModel: viewModel)
            .onAppear {
                viewModel.previewSelectFirstItem()
            }
    }
}

#Preview("Packing Session") {
    PackingSessionPreviewContainer()
        .modelContainer(PreviewFixtures.container)
}

extension PackingSessionViewModel {
    func previewSelectFirstItem() {
        guard let index = steps.firstIndex(where: { step in
            if case .runCoil = step { return true }
            return false
        }) else { return }
        currentIndex = index
    }
}
#endif

private extension AVSpeechSynthesisVoice {
    static func preferredSiriVoice(forLanguage language: String) -> AVSpeechSynthesisVoice? {
        let matchingVoices = speechVoices().filter { $0.language == language }
        if let siriVoice = matchingVoices.first(where: { voice in
            voice.identifier.contains(".Siri_") || voice.name.lowercased().contains("siri")
        }) {
            return siriVoice
        }
        if let enhancedVoice = matchingVoices.first(where: { $0.quality == .enhanced }) {
            return enhancedVoice
        }
        return matchingVoices.first ?? AVSpeechSynthesisVoice(language: language)
    }
}

private extension Error {
    var shouldSuppressForAudioSession: Bool {
        let nsError = self as NSError
        if nsError.domain == NSOSStatusErrorDomain && nsError.code == -50 {
            return true
        }
        return false
    }
}
