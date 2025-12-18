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

struct MachineCompletionInfo: Equatable, Identifiable {
    let id = UUID()
    let machineCode: String?
    let machineName: String?
    let machineDescription: String?
    let locationName: String?
    let message: String
}

@MainActor
class PackingSessionViewModel: NSObject, ObservableObject {
    let runId: String
    let packingSessionId: String
    let session: AuthSession
    let service: RunsServicing
    
    @Published var audioCommands: [AudioCommandsResponse.AudioCommand] = []
    @Published var currentIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isSpeaking: Bool = false
    @Published var isSessionComplete: Bool = false
    @Published var completedItems: Set<String> = []
    @Published var showingChocolateBoxesSheet = false
    @Published var showingCountPointerSheet = false
    @Published var selectedPickItemForCountPointer: RunDetail.PickItem?
    @Published var selectedPickItemForFreshChest: RunDetail.PickItem?
    @Published var updatingPickIds: Set<String> = []
    @Published var updatingSkuIds: Set<String> = []
    @Published private(set) var runDetail: RunDetail?
    @Published private(set) var chocolateBoxes: [RunDetail.ChocolateBox] = []
    @Published var machineCompletionInfo: MachineCompletionInfo?
    @Published var isStoppingSession = false
    
    private let synthesizer = AVSpeechSynthesizer()
    private let silentLoop = SilentLoopPlayer()
    private var audioSessionConfigured = false
    private var remoteCommandCenterConfigured = false
    private var announcedMachineIdentifiers: Set<String> = []
    private var hasSyncedFinishedSession = false
    private var isFinishingSessionRemotely = false
    
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
    
    var currentMachine: RunDetail.Machine? {
        guard let runDetail else { return nil }
        if let machineId = currentCommand?.machineId, !machineId.isEmpty {
            if let machine = runDetail.machines.first(where: { $0.id == machineId }) {
                return machine
            }
        }
        // Fallback to the pick item's machine if the command didn't include one
        if let pickItemMachine = currentPickItem?.machine {
            return pickItemMachine
        }
        return nil
    }
    
    var currentLocationName: String? {
        if let commandLocation = currentCommand?.locationName,
           !commandLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return commandLocation
        }
        if let machineLocation = currentMachine?.location?.name,
           !machineLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return machineLocation
        }
        if let pickLocation = currentPickItem?.machine?.location?.name,
           !pickLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return pickLocation
        }
        return nil
    }
    
    var currentLocationMachines: [RunDetail.Machine] {
        guard let runDetail = runDetail else { 
            print("🍫 No runDetail available")
            return [] 
        }
        
        // Find the most recent location command to determine current location
        let locationCommands = audioCommands.filter { $0.type == "location" }
        print("🍫 Found \(locationCommands.count) location commands")
        guard let currentLocationCommand = locationCommands.last,
              let locationName = currentLocationCommand.locationName else { 
            print("🍫 No current location command or location name")
            return [] 
        }
        
        print("🍫 Current location name: '\(locationName)'")
        print("🍫 Total machines in run: \(runDetail.machines.count)")
        
        // Find machines at this location
        let machines = runDetail.machines.filter { machine in
            let matches = machine.location?.name == locationName
            if matches {
                print("🍫 Found machine at location: \(machine.code) - \(machine.location?.name ?? "no location")")
            }
            return matches
        }
        print("🍫 Machines at current location: \(machines.count)")
        return machines
    }
    
    var currentPickItem: RunDetail.PickItem? {
        guard let currentCommand = currentCommand,
              currentCommand.type == "item",
              !currentCommand.pickEntryIds.isEmpty,
              let runDetail = runDetail else { return nil }
        
        let pickEntryId = currentCommand.pickEntryIds.first!
        return runDetail.pickItems.first { $0.id == pickEntryId }
    }
    
    init(runId: String, packingSessionId: String, session: AuthSession, service: RunsServicing) {
        self.runId = runId
        self.packingSessionId = packingSessionId
        self.session = session
        self.service = service
        super.init()
        synthesizer.delegate = self
    }
    
    func loadAudioCommands() async {
        isLoading = true
        errorMessage = nil
        machineCompletionInfo = nil
        announcedMachineIdentifiers.removeAll()
        isSessionComplete = false
        currentIndex = 0
        
        do {
            async let audioCommandsTask = service.fetchAudioCommands(for: runId, packingSessionId: packingSessionId, credentials: session.credentials)
            async let runDetailTask = service.fetchRunDetail(withId: runId, credentials: session.credentials)
            async let chocolateBoxesTask = service.fetchChocolateBoxes(for: runId, credentials: session.credentials)
            
            let response = try await audioCommandsTask
            let detail = try await runDetailTask
            let boxes = try await chocolateBoxesTask

            audioCommands = response.audioCommands
            let sessionPickIds = Set(response.audioCommands.filter { $0.type == "item" }.flatMap { $0.pickEntryIds })
            runDetail = detail
            chocolateBoxes = boxes.sorted { $0.number < $1.number }
            completedItems = Set(
                detail.pickItems
                    .filter { $0.isPicked && sessionPickIds.contains($0.id) }
                    .map { $0.id }
            )

            if response.hasItems {
                if let pendingIndex = firstPendingItemIndex() {
                    currentIndex = contextStartIndex(forPendingItemAt: pendingIndex)
                    isSessionComplete = false
                } else {
                    currentIndex = audioCommands.count
                    isSessionComplete = true
                }
            } else {
                // No items are assigned to this session; abandon to unlock picks
                await handleSessionLoadFailure("No items to pack in this run.")
                return
            }

            if response.hasItems {
                configureAudioSessionIfNeeded()
                setupRemoteCommandCenter()
                silentLoop.start()
                updateNowPlayingInfo()
                if isSessionComplete {
                    completeSession()
                } else {
                    await speakCurrentCommand()
                }
            } else {
                await handleSessionLoadFailure("No items to pack in this run.")
            }
        } catch {
            await handleSessionLoadFailure(error.localizedDescription)
        }
        
        isLoading = false
    }
    
    func goForward() async {
        interruptSpeechPlayback()
        if await acknowledgeMachineCompletionIfNeeded() {
            return
        }
        
        guard !isSessionComplete else { return }
        
        let finishedCommand = currentCommand
        
        // Mark current item as completed if it's an item
        if let currentCommand = finishedCommand, currentCommand.type == "item" {
            await markAsPacked(pickEntryIds: currentCommand.pickEntryIds)
        }
        
        if let finishedCommand, maybePauseForMachineCompletion(after: finishedCommand) {
            return
        }
        
        await advanceToNextPlayableCommand()
    }
    
    func goBack() async {
        interruptSpeechPlayback()
        if machineCompletionInfo != nil {
            machineCompletionInfo = nil
            return
        }
        
        guard canGoBack else { return }
        
        currentIndex = max(currentIndex - 1, 0)
        updateNowPlayingInfo()
        await speakCurrentCommand(skippingCompleted: false)
    }
    
    func skipCurrent() async {
        interruptSpeechPlayback()
        if await acknowledgeMachineCompletionIfNeeded() {
            return
        }
        
        guard !isSessionComplete else { return }
        
        let finishedCommand = currentCommand
        
        // Mark as skipped if it's an item
        if let currentCommand = finishedCommand, currentCommand.type == "item" {
            await markAsSkipped(pickEntryIds: currentCommand.pickEntryIds)
        }
        
        if let finishedCommand, maybePauseForMachineCompletion(after: finishedCommand) {
            return
        }
        
        await advanceToNextPlayableCommand()
    }
    
    func repeatCurrent() async {
        interruptSpeechPlayback()
        if let completionInfo = machineCompletionInfo {
            speakMachineCompletion(message: completionInfo.message)
            return
        }
        
        updateNowPlayingInfo()
        await speakCurrentCommand(skippingCompleted: false)
    }
    
    func stopSession() async -> Bool {
        stopAudio()
        if isStoppingSession {
            return false
        }

        isStoppingSession = true
        defer { isStoppingSession = false }

        if isSessionComplete || hasSyncedFinishedSession {
            let didFinish = await sendFinishSessionRequestIfNeeded()
            if didFinish {
                await refreshRunDetail()
            } else {
                audioCommands = []
                currentIndex = 0
            }
            return didFinish
        }

        do {
            _ = try await service.abandonPackingSession(
                runId: runId,
                packingSessionId: packingSessionId,
                credentials: session.credentials
            )
            await refreshRunDetail()
            return true
        } catch {
            errorMessage = error.localizedDescription
            audioCommands = []
            currentIndex = 0
            return false
        }
    }
    
    func pauseSession() {
        stopAudio()
    }
    
    private func finishSessionRemotelyIfNeeded() {
        Task { [weak self] in
            _ = await self?.sendFinishSessionRequestIfNeeded()
        }
    }
    
    @discardableResult
    private func sendFinishSessionRequestIfNeeded() async -> Bool {
        if hasSyncedFinishedSession {
            return true
        }

        if isFinishingSessionRemotely {
            while isFinishingSessionRemotely && !hasSyncedFinishedSession {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return hasSyncedFinishedSession
        }
        
        isFinishingSessionRemotely = true
        defer { isFinishingSessionRemotely = false }
        
        do {
            _ = try await service.finishPackingSession(
                runId: runId,
                packingSessionId: packingSessionId,
                credentials: session.credentials
            )
            hasSyncedFinishedSession = true
            await refreshRunDetail()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
    
    private func stopAudio() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        silentLoop.stop()
        deactivateAudioSession()
        deactivateRemoteCommandCenter()
        clearNowPlayingInfo()
        machineCompletionInfo = nil
    }

    private func interruptSpeechPlayback() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        updatePlaybackState()
    }
    
    private func speakCurrentCommand(skippingCompleted: Bool = true) async {
        guard !audioCommands.isEmpty else { return }
        
        if skippingCompleted {
            // Skip over already-completed item commands so we don't re-read packed items
            if let nextIndex = nextPlayableIndex(startingAt: currentIndex) {
                currentIndex = nextIndex
            } else {
                completeSession()
                return
            }
        } else if currentIndex < 0 || currentIndex >= audioCommands.count {
            return
        }
        
        guard let command = currentCommand else { return }

        interruptSpeechPlayback()

        let utterance = AVSpeechUtterance(string: command.audioCommand)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // Use modern Apple voices with enhanced quality
        configurePreferredVoice(for: utterance)
        isSpeaking = true
        updateNowPlayingInfo()
        updatePlaybackState()
        synthesizer.speak(utterance)
    }
    
    private func markAsPacked(pickEntryIds: [String]) async {
        let ids = pickEntryIds.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        
        do {
            try await service.updatePickItemStatuses(
                runId: runId,
                pickIds: ids,
                isPicked: true,
                credentials: session.credentials
            )
            ids.forEach { completedItems.insert($0) }
        } catch {
            print("Failed to mark items as packed: \(error)")
        }
    }
    
    private func markAsSkipped(pickEntryIds: [String]) async {
        let ids = pickEntryIds.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        
        do {
            try await service.updatePickItemStatuses(
                runId: runId,
                pickIds: ids,
                isPicked: false,
                credentials: session.credentials
            )
        } catch {
            print("Failed to mark items as skipped: \(error)")
        }
    }

    private func firstPendingItemIndex() -> Int? {
        audioCommands.firstIndex { command in
            guard command.type == "item" else { return false }
            return !command.pickEntryIds.allSatisfy(completedItems.contains)
        }
    }
    
    private func contextStartIndex(forPendingItemAt index: Int) -> Int {
        guard index < audioCommands.count else { return audioCommands.count - 1 }
        let target = audioCommands[index]
        var nearestMachineIndex: Int?

        for idx in stride(from: index - 1, through: 0, by: -1) {
            let command = audioCommands[idx]
            if command.type == "location", command.locationId == target.locationId {
                return idx
            }
            if command.type == "machine", command.machineId == target.machineId, nearestMachineIndex == nil {
                nearestMachineIndex = idx
            }
        }

        return nearestMachineIndex ?? index
    }
    
    private func hasPendingItemsForMachine(id: String?, after index: Int) -> Bool {
        guard index + 1 < audioCommands.count else { return false }
        for idx in (index + 1)..<audioCommands.count {
            let command = audioCommands[idx]
            guard command.type == "item" else { continue }
            if let machineId = id, let candidateId = command.machineId, candidateId != machineId {
                continue
            }
            if !command.pickEntryIds.allSatisfy(completedItems.contains) {
                return true
            }
        }
        return false
    }
    
    private func hasPendingItemsForLocation(id: String?, after index: Int) -> Bool {
        guard index + 1 < audioCommands.count else { return false }
        for idx in (index + 1)..<audioCommands.count {
            let command = audioCommands[idx]
            guard command.type == "item" else { continue }
            if let locationId = id, let candidateId = command.locationId, candidateId != locationId {
                continue
            }
            if !command.pickEntryIds.allSatisfy(completedItems.contains) {
                return true
            }
        }
        return false
    }
    
    private func nextPlayableIndex(startingAt index: Int) -> Int? {
        var idx = index
        while idx < audioCommands.count {
            let command = audioCommands[idx]
            
            if command.type == "item" {
                if command.pickEntryIds.allSatisfy(completedItems.contains) {
                    idx += 1
                    continue
                }
                return idx
            }
            
            if command.type == "machine" {
                if hasPendingItemsForMachine(id: command.machineId, after: idx) {
                    return idx
                } else {
                    idx += 1
                    continue
                }
            }
            
            if command.type == "location" {
                if hasPendingItemsForLocation(id: command.locationId, after: idx) {
                    return idx
                } else {
                    idx += 1
                    continue
                }
            }
            
            return idx
        }
        return nil
    }
    
    private func completeSession() {
        isSessionComplete = true
        currentIndex = audioCommands.count
        finishSessionRemotelyIfNeeded()
        
        updateNowPlayingInfoForCompletion()
        
        interruptSpeechPlayback()

        // Announce completion with enhanced voice
        let utterance = AVSpeechUtterance(string: "Packing session complete. Great job.")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.1 // Slightly more upbeat for completion
        utterance.volume = 1.0
        
        configurePreferredVoice(for: utterance)
        synthesizer.speak(utterance)
    }
    
    private func speakMachineCompletion(message: String) {
        interruptSpeechPlayback()
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        configurePreferredVoice(for: utterance)
        synthesizer.speak(utterance)
    }
    
    private func configurePreferredVoice(for utterance: AVSpeechUtterance) {
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
    }

    private func refreshRunDetail() async {
        do {
            let detail = try await service.fetchRunDetail(withId: runId, credentials: session.credentials)
            await MainActor.run {
                runDetail = detail
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func advanceToNextPlayableCommand() async {
        if let nextIndex = nextPlayableIndex(startingAt: currentIndex + 1) {
            currentIndex = nextIndex
            updateNowPlayingInfo()
            await speakCurrentCommand()
        } else {
            completeSession()
        }
    }
    
    @discardableResult
    private func acknowledgeMachineCompletionIfNeeded() async -> Bool {
        guard let _ = machineCompletionInfo else { return false }
        machineCompletionInfo = nil
        await advanceToNextPlayableCommand()
        return true
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

    private func handleSessionLoadFailure(_ message: String) async {
        errorMessage = message
        _ = await stopSession()
        isLoading = false
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
        
        // Some devices use skip backward for the back control; map it to repeat as well
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            Task { @MainActor in
                await self?.repeatCurrent()
            }
            return .success
        }
        commandCenter.skipBackwardCommand.preferredIntervals = [0]
        
        // Enable the commands
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = true
        
        remoteCommandCenterConfigured = true
    }
    
    private func deactivateRemoteCommandCenter() {
        guard remoteCommandCenterConfigured else { return }
        
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.isEnabled = false
        
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
    
    // MARK: - Cold Chest Status Management
    func toggleColdChestStatus(_ pickItem: RunDetail.PickItem) async {
        guard let skuId = pickItem.sku?.id else { return }
        
        updatingSkuIds.insert(skuId)
        
        let newFreshStatus = !(pickItem.sku?.isFreshOrFrozen ?? false)
        
        do {
            try await service.updateSkuColdChestStatus(
                skuId: skuId,
                isFreshOrFrozen: newFreshStatus,
                credentials: session.credentials
            )
            await refreshRunDetail()
        } catch {
            print("Failed to update SKU cold chest status: \(error)")
        }
        
        updatingSkuIds.remove(skuId)
    }

    // MARK: - Expiry Override Management
    func replaceExpiryOverrides(_ pickItem: RunDetail.PickItem, overrides: [UpdateExpirySheet.OverridePayload]) async {
        updatingPickIds.insert(pickItem.id)
        defer { updatingPickIds.remove(pickItem.id) }

        do {
            try await service.replacePickEntryExpiryOverrides(
                runId: runId,
                pickId: pickItem.id,
                overrides: overrides.map { (expiryDate: $0.expiryDate, quantity: $0.quantity) },
                credentials: session.credentials
            )
            await refreshRunDetail()
        } catch {
            print("Failed to update pick entry expiry: \(error)")
        }
    }
    
    // MARK: - Count Pointer Management
    func updateCountPointer(_ pickItem: RunDetail.PickItem, newPointer: String) async {
        guard let skuId = pickItem.sku?.id else { return }
        
        updatingSkuIds.insert(skuId)
        
        do {
            try await service.updateSkuCountPointer(
                skuId: skuId,
                countNeededPointer: newPointer,
                credentials: session.credentials
            )
            // Reload audio commands to reflect the change
            await loadAudioCommands()
            await MainActor.run {
                selectedPickItemForCountPointer = nil
                showingCountPointerSheet = false
            }
        } catch {
            print("Failed to update SKU count pointer: \(error)")
        }
        
        updatingSkuIds.remove(skuId)
    }
    
    func updateOverride(_ pickItem: RunDetail.PickItem, overrideValue: Int?) async {
        updatingPickIds.insert(pickItem.id)
        
        do {
            try await service.updatePickEntryOverride(
                runId: runId,
                pickId: pickItem.id,
                overrideCount: overrideValue,
                credentials: session.credentials
            )
            await loadAudioCommands()
            await MainActor.run {
                selectedPickItemForCountPointer = nil
                showingCountPointerSheet = false
            }
        } catch {
            print("Failed to update pick override: \(error)")
        }
        
        updatingPickIds.remove(pickItem.id)
    }
    
    // MARK: - Chocolate Boxes Management
    func createChocolateBox(number: Int, machineId: String) async throws {
        do {
            _ = try await service.createChocolateBox(
                for: runId,
                number: number,
                machineId: machineId,
                credentials: session.credentials
            )
            // Refresh chocolate boxes after creation
            await refreshChocolateBoxes()
        } catch {
            throw error
        }
    }

    func deleteChocolateBox(boxId: String) async {
        do {
            try await service.deleteChocolateBox(for: runId, boxId: boxId, credentials: session.credentials)
            // Refresh chocolate boxes after deletion
            await refreshChocolateBoxes()
        } catch {
            print("Failed to delete chocolate box: \(error)")
        }
    }
    
    private func refreshChocolateBoxes() async {
        do {
            let boxes = try await service.fetchChocolateBoxes(for: runId, credentials: session.credentials)
            chocolateBoxes = boxes.sorted { $0.number < $1.number }
        } catch {
            print("Failed to refresh chocolate boxes: \(error)")
        }
    }
    
    // MARK: - Machine Completion Announcements
    private func maybePauseForMachineCompletion(after command: AudioCommandsResponse.AudioCommand) -> Bool {
        guard let identifier = machineIdentifier(for: command) else { return false }
        guard !announcedMachineIdentifiers.contains(identifier) else { return false }
        guard !hasRemainingItems(forMachineIdentifier: identifier, after: command.id) else { return false }

        announcedMachineIdentifiers.insert(identifier)
        let info = MachineCompletionInfo(
            machineCode: command.machineCode,
            machineName: command.machineName,
            machineDescription: command.machineDescription,
            locationName: command.locationName,
            message: machineCompletionMessage(for: command)
        )
        machineCompletionInfo = info
        speakMachineCompletion(message: info.message)
        return true
    }

    private func hasRemainingItems(forMachineIdentifier identifier: String, after commandId: String) -> Bool {
        guard let baseIndex = audioCommands.firstIndex(where: { $0.id == commandId }) else { return false }
        guard baseIndex + 1 < audioCommands.count else { return false }

        for index in (baseIndex + 1)..<audioCommands.count {
            let candidate = audioCommands[index]
            guard let candidateIdentifier = machineIdentifier(for: candidate) else { continue }
            if candidateIdentifier == identifier && candidate.type == "item" {
                return true
            }
        }

        return false
    }

    private func machineIdentifier(for command: AudioCommandsResponse.AudioCommand) -> String? {
        if let machineId = command.machineId?.trimmingCharacters(in: .whitespacesAndNewlines), !machineId.isEmpty {
            return machineId
        }
        if let machineCode = command.machineCode?.trimmingCharacters(in: .whitespacesAndNewlines), !machineCode.isEmpty {
            return "code-\(machineCode)"
        }
        if let machineName = command.machineName?.trimmingCharacters(in: .whitespacesAndNewlines), !machineName.isEmpty {
            return "name-\(machineName)"
        }
        return nil
    }

    private func machineCompletionMessage(for command: AudioCommandsResponse.AudioCommand) -> String {
        let trimmedDescription = command.machineDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedLocation = command.locationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var subject: String
        if let machineCode = command.machineCode?.trimmingCharacters(in: .whitespacesAndNewlines), !machineCode.isEmpty {
            subject = "Machine \(machineCode)"
        } else if let machineName = command.machineName?.trimmingCharacters(in: .whitespacesAndNewlines), !machineName.isEmpty {
            subject = "Machine \(machineName)"
        } else if !trimmedDescription.isEmpty {
            subject = trimmedDescription
        } else {
            subject = "This machine"
        }

        if !trimmedLocation.isEmpty {
            return "\(subject) complete at \(trimmedLocation)."
        }
        return "\(subject) complete."
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
