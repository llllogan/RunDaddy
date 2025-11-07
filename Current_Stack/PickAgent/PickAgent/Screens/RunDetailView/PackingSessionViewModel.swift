//
//  PackingSessionViewModel.swift
//  PickAgent
//
//  Created by Logan Janssen on 11/6/2025.
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer

@MainActor
class PackingSessionViewModel: NSObject, ObservableObject {
    let runId: String
    let session: AuthSession
    let service: RunsServicing
    
    @Published var audioCommands: [AudioCommandsResponse.AudioCommand] = []
    @Published var currentIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isSpeaking: Bool = false
    @Published var isSessionComplete: Bool = false
    @Published var completedItems: Set<String> = []
    
    private let synthesizer = AVSpeechSynthesizer()
    private let silentLoop = SilentLoopPlayer()
    private var audioSessionConfigured = false
    private var remoteCommandCenterConfigured = false
    
    var currentCommand: AudioCommandsResponse.AudioCommand? {
        guard currentIndex >= 0 && currentIndex < audioCommands.count else { return nil }
        return audioCommands[currentIndex]
    }
    
    var totalItems: Int {
        audioCommands.filter { $0.type == "item" }.count
    }
    
    var completedCount: Int {
        completedItems.count
    }
    
    var progress: Double {
        guard totalItems > 0 else { return 0 }
        return Double(completedCount) / Double(totalItems)
    }
    
    var canGoBack: Bool {
        currentIndex > 0
    }
    
    var canGoForward: Bool {
        currentIndex < audioCommands.count - 1
    }
    
    init(runId: String, session: AuthSession, service: RunsServicing) {
        self.runId = runId
        self.session = session
        self.service = service
        super.init()
        synthesizer.delegate = self
        setupRemoteCommandCenter()
    }
    
    func loadAudioCommands() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await service.fetchAudioCommands(for: runId, credentials: session.credentials)
            audioCommands = response.audioCommands
            currentIndex = 0
            completedItems.removeAll()
            isSessionComplete = false
            
            if response.hasItems {
                configureAudioSessionIfNeeded()
                setupRemoteCommandCenter()
                silentLoop.start()
                updateNowPlayingInfo()
                await speakCurrentCommand()
            } else {
                errorMessage = "No items to pack in this run"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func goForward() async {
        guard !isSessionComplete else { return }
        
        // Mark current item as completed if it's an item
        if let currentCommand = currentCommand, currentCommand.type == "item" {
            await markAsPacked(pickEntryIds: currentCommand.pickEntryIds)
        }
        
        if canGoForward {
            currentIndex += 1
            updateNowPlayingInfo()
            await speakCurrentCommand()
        } else {
            completeSession()
        }
    }
    
    func goBack() async {
        guard canGoBack else { return }
        
        currentIndex -= 1
        updateNowPlayingInfo()
        await speakCurrentCommand()
    }
    
    func skipCurrent() async {
        guard !isSessionComplete else { return }
        
        // Mark as skipped if it's an item
        if let currentCommand = currentCommand, currentCommand.type == "item" {
            await markAsSkipped(pickEntryIds: currentCommand.pickEntryIds)
        }
        
        if canGoForward {
            currentIndex += 1
            updateNowPlayingInfo()
            await speakCurrentCommand()
        } else {
            completeSession()
        }
    }
    
    func repeatCurrent() async {
        updateNowPlayingInfo()
        await speakCurrentCommand()
    }
    
    func stopSession() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        silentLoop.stop()
        deactivateAudioSession()
        deactivateRemoteCommandCenter()
        clearNowPlayingInfo()
    }
    
    private func speakCurrentCommand() async {
        guard let command = currentCommand else { return }
        
        let utterance = AVSpeechUtterance(string: command.audioCommand)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // Use modern Apple voices with enhanced quality
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let preferredVoice = voices.first { voice in
            // Prefer enhanced quality voices for English
            voice.language.hasPrefix("en") && 
            voice.quality == .enhanced &&
            (voice.name.contains("Siri") || 
             voice.name.contains("Alex") || 
             voice.name.contains("Daniel") ||
             voice.name.contains("Karen") ||
             voice.name.contains("Moira"))
        } ?? voices.first { voice in
            // Fallback to any enhanced English voice
            voice.language.hasPrefix("en") && voice.quality == .enhanced
        } ?? voices.first { voice in
            // Final fallback to any English voice
            voice.language.hasPrefix("en")
        } ?? voices.first
        
        if let voice = preferredVoice {
            utterance.voice = voice
        }
        
        isSpeaking = true
        updateNowPlayingInfo()
        updatePlaybackState()
        synthesizer.speak(utterance)
    }
    
    private func markAsPacked(pickEntryIds: [String]) async {
        guard !pickEntryIds.isEmpty else { return }
        
        for pickEntryId in pickEntryIds {
            guard !pickEntryId.isEmpty else { continue }
            
            do {
                try await service.updatePickItemStatus(
                    runId: runId,
                    pickId: pickEntryId,
                    status: "PICKED",
                    credentials: session.credentials
                )
                completedItems.insert(pickEntryId)
            } catch {
                print("Failed to mark item as packed: \(error)")
            }
        }
    }
    
    private func markAsSkipped(pickEntryIds: [String]) async {
        guard !pickEntryIds.isEmpty else { return }
        
        for pickEntryId in pickEntryIds {
            guard !pickEntryId.isEmpty else { continue }
            
            do {
                try await service.updatePickItemStatus(
                    runId: runId,
                    pickId: pickEntryId,
                    status: "SKIPPED",
                    credentials: session.credentials
                )
            } catch {
                print("Failed to mark item as skipped: \(error)")
            }
        }
    }
    
    private func completeSession() {
        isSessionComplete = true
        currentIndex = audioCommands.count
        
        updateNowPlayingInfoForCompletion()
        
        // Announce completion with enhanced voice
        let utterance = AVSpeechUtterance(string: "Packing session complete. Great job.")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.1 // Slightly more upbeat for completion
        utterance.volume = 1.0
        
        // Use the same voice selection logic as regular commands
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let preferredVoice = voices.first { voice in
            voice.language.hasPrefix("en") && 
            voice.quality == .enhanced &&
            (voice.name.contains("Siri") || 
             voice.name.contains("Alex") || 
             voice.name.contains("Daniel") ||
             voice.name.contains("Karen") ||
             voice.name.contains("Moira"))
        } ?? voices.first { voice in
            voice.language.hasPrefix("en") && voice.quality == .enhanced
        } ?? voices.first { voice in
            voice.language.hasPrefix("en")
        } ?? voices.first
        
        if let voice = preferredVoice {
            utterance.voice = voice
        }
        
        synthesizer.speak(utterance)
    }
    
    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Use modern audio session configuration with playback control support
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                policy: .default,
                options: [
                    .duckOthers,
                    .interruptSpokenAudioAndMixWithOthers,
                    .allowBluetoothA2DP,
                    .allowAirPlay,
                    .allowBluetoothHFP
                ]
            )
            
            // Configure for optimal speech playback
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Note: routeSharingPolicy is get-only in iOS 15.0+
            
            audioSessionConfigured = true
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func deactivateAudioSession() {
        guard audioSessionConfigured else { return }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        audioSessionConfigured = false
    }
    
    private func setupRemoteCommandCenter() {
        guard !remoteCommandCenterConfigured else { return }
        
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Next track command -> goForward
        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            Task { @MainActor in
                await self?.goForward()
            }
            return .success
        }
        
        // Previous track command -> repeatCurrent
        commandCenter.previousTrackCommand.addTarget { [weak self] event in
            Task { @MainActor in
                await self?.repeatCurrent()
            }
            return .success
        }
        
        // Enable the commands
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        
        remoteCommandCenterConfigured = true
    }
    
    private func deactivateRemoteCommandCenter() {
        guard remoteCommandCenterConfigured else { return }
        
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        
        remoteCommandCenterConfigured = false
    }
    
    private func updateNowPlayingInfo() {
        var info: [String: Any] = [:]
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyPlaybackRate] = isSpeaking ? 1 : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = silentLoop.currentTime
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = audioCommands.count
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = min(currentIndex, max(audioCommands.count - 1, 0))

        if let command = currentCommand {
            info[MPMediaItemPropertyTitle] = command.audioCommand
            info[MPMediaItemPropertyArtist] = command.type.capitalized
        } else {
            info[MPMediaItemPropertyTitle] = "Packing Session"
            info[MPMediaItemPropertyArtist] = "PickAgent"
        }

        info[MPMediaItemPropertyAlbumTitle] = "Run \(runId)"
        info[MPMediaItemPropertyPlaybackDuration] = 86400

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func updateNowPlayingInfoForCompletion() {
        var info: [String: Any] = [:]
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyPlaybackRate] = 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = silentLoop.currentTime
        info[MPMediaItemPropertyTitle] = "Session Complete"
        info[MPMediaItemPropertyArtist] = "PickAgent"
        info[MPMediaItemPropertyAlbumTitle] = "Run \(runId)"
        info[MPMediaItemPropertyPlaybackDuration] = 86400
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func updatePlaybackState() {
        MPNowPlayingInfoCenter.default().playbackState = isSpeaking ? .playing : .paused
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isSpeaking ? 1 : 0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = silentLoop.currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

extension PackingSessionViewModel: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = true
            updatePlaybackState()
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            updatePlaybackState()
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            updatePlaybackState()
        }
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
