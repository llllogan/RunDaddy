//
//  PackingSessionViewModel.swift
//  PickAgent
//
//  Created by Logan Janssen on 11/6/2025.
//

import Foundation
import AVFoundation
import Combine

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
    private var audioSessionConfigured = false
    
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
            await markAsPacked(pickEntryId: currentCommand.pickEntryId)
        }
        
        if canGoForward {
            currentIndex += 1
            await speakCurrentCommand()
        } else {
            completeSession()
        }
    }
    
    func goBack() async {
        guard canGoBack else { return }
        
        currentIndex -= 1
        await speakCurrentCommand()
    }
    
    func skipCurrent() async {
        guard !isSessionComplete else { return }
        
        // Mark as skipped if it's an item
        if let currentCommand = currentCommand, currentCommand.type == "item" {
            await markAsSkipped(pickEntryId: currentCommand.pickEntryId)
        }
        
        if canGoForward {
            await goForward()
        } else {
            completeSession()
        }
    }
    
    func repeatCurrent() async {
        await speakCurrentCommand()
    }
    
    func stopSession() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        deactivateAudioSession()
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
        synthesizer.speak(utterance)
    }
    
    private func markAsPacked(pickEntryId: String) async {
        guard !pickEntryId.isEmpty else { return }
        
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
    
    private func markAsSkipped(pickEntryId: String) async {
        guard !pickEntryId.isEmpty else { return }
        
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
    
    private func completeSession() {
        isSessionComplete = true
        currentIndex = audioCommands.count
        
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
            
            // Use modern audio session configuration
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
}

extension PackingSessionViewModel: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = true
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }
}
