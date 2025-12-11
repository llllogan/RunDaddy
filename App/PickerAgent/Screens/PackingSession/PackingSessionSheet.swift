//
//  PackingSessionSheet.swift
//  PickAgent
//
//  Created by Logan Janssen on 11/6/2025.
//

import SwiftUI
import AVFoundation
import UIKit

struct PackingSessionSheet: View {
    private enum SessionEndAction {
        case none
        case abandon
        case pause
    }

    let runId: String
    let packingSessionId: String
    let session: AuthSession
    let onAbandon: (() -> Void)?
    let onPause: (() -> Void)?
    @StateObject private var viewModel: PackingSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddChocolateBoxAlert = false
    @State private var chocolateBoxNumberInput = ""
    @State private var chocolateBoxErrorMessage: String?
    @State private var isCreatingChocolateBox = false
    @State private var targetMachineForChocolateBox: RunDetail.Machine?
    @State private var abandonOnDisappear = true
    @State private var lastEndAction: SessionEndAction = .none
    
    init(runId: String, packingSessionId: String, session: AuthSession, service: RunsServicing = RunsService(), onAbandon: (() -> Void)? = nil, onPause: (() -> Void)? = nil) {
        self.runId = runId
        self.packingSessionId = packingSessionId
        self.session = session
        self.onAbandon = onAbandon
        self.onPause = onPause
        _viewModel = StateObject(wrappedValue: PackingSessionViewModel(runId: runId, packingSessionId: packingSessionId, session: session, service: service))
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    content(for: layoutMode(for: geometry.size))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Stop Packing", systemImage: "stop.fill") {
                        Task {
                            let didStop = await viewModel.stopSession()
                            if didStop {
                                abandonOnDisappear = false
                                lastEndAction = .abandon
                                onAbandon?()
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isStoppingSession)
                    .tint(.red)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Pause", systemImage: "pause.fill") {
                        abandonOnDisappear = false
                        lastEndAction = .pause
                        viewModel.pauseSession()
                        onPause?()
                        dismiss()
                    }
                    .tint(.blue)
                }
                
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Skip") {
                        Task {
                            await viewModel.skipCurrent()
                        }
                    }
                    .disabled(viewModel.isSessionComplete || viewModel.isSpeaking)
                    
                    Spacer()
                    
                    Button {
                        Task {
                            await viewModel.goBack()
                        }
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    .disabled(!viewModel.canGoBack || viewModel.isSpeaking)
                    
                    Button {
                        Task {
                            await viewModel.repeatCurrent()
                        }
                    } label: {
                        Image(systemName: "repeat")
                    }
                    .disabled(viewModel.currentCommand == nil || viewModel.isSpeaking)
                    
                    Button {
                        Task {
                            if viewModel.isSessionComplete {
                                let didStop = await viewModel.stopSession()
                                if didStop {
                                    abandonOnDisappear = false
                                    lastEndAction = .abandon
                                    onAbandon?()
                                    dismiss()
                                }
                            } else {
                                await viewModel.goForward()
                            }
                        }
                    } label: {
                        Image(systemName: viewModel.isSessionComplete ? "checkmark.circle.fill" : "forward.fill")
                    }
                    .tint(viewModel.isSessionComplete ? .green : .blue)
                    .disabled(viewModel.isSpeaking || viewModel.isStoppingSession)
                }
                
            }
        }
        .sheet(isPresented: $viewModel.showingCountPointerSheet) {
            if let pickItem = viewModel.selectedPickItemForCountPointer {
                CountPointerSelectionSheet(
                    pickItem: pickItem,
                    onDismiss: {
                        viewModel.selectedPickItemForCountPointer = nil
                        viewModel.showingCountPointerSheet = false
                    },
                    onPointerSelected: { newPointer in
                        Task {
                            await viewModel.updateCountPointer(pickItem, newPointer: newPointer)
                        }
                    },
                    onOverrideSaved: { overrideValue in
                        await viewModel.updateOverride(pickItem, overrideValue: overrideValue)
                    },
                    viewModel: RunDetailViewModel(runId: runId, session: session, service: viewModel.service)
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .textFieldAlert(
            isPresented: $showingAddChocolateBoxAlert,
            text: $chocolateBoxNumberInput,
            title: "Add Chocolate Box",
            message: chocolateBoxErrorMessage,
            confirmTitle: "Create",
            cancelTitle: "Cancel",
            keyboardType: .numberPad,
            allowedCharacterSet: .decimalDigits,
            onConfirm: {
                chocolateBoxErrorMessage = nil
                submitChocolateBoxEntry()
            },
            onCancel: {
                chocolateBoxNumberInput = ""
                chocolateBoxErrorMessage = nil
                targetMachineForChocolateBox = nil
            }
        )

        .onAppear {
            abandonOnDisappear = true
            lastEndAction = .none
            Task {
                await viewModel.loadAudioCommands()
            }
        }
        .onDisappear {
            switch lastEndAction {
            case .abandon:
                break
            case .pause:
                // Already paused via explicit action
                break
            case .none:
                if abandonOnDisappear {
                    Task {
                        let didStop = await viewModel.stopSession()
                        if didStop {
                            onAbandon?()
                        }
                    }
                } else {
                    viewModel.pauseSession()
                    onPause?()
                }
            }
        }
    }

    @ViewBuilder
    private func content(for layout: PackingSessionInstructionLayout) -> some View {
        VStack(spacing: 16) {
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading packing session...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.packingSessionBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("Error")
                        .font(.headline.weight(.semibold))
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task {
                            await viewModel.loadAudioCommands()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.packingSessionBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if viewModel.isSessionComplete {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.green)
                    Text("All items packed")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Great job! You've completed the packing session.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.packingSessionBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if let command = viewModel.currentCommand {
                CurrentCommandView(
                    layout: layout,
                    command: command,
                    machineCompletionInfo: viewModel.machineCompletionInfo,
                    skuType: viewModel.currentPickItem?.sku?.type,
                    progressInfo: progressInfo(for: command),
                    chocolateBoxNumbers: chocolateBoxNumbersForCurrentMachine,
                    isFreshOrFrozen: viewModel.currentPickItem?.sku?.isFreshOrFrozen ?? false,
                    canAddChocolateBox: viewModel.currentMachine != nil,
                    canToggleFreshStatus: viewModel.currentPickItem != nil,
                    onAddChocolateBoxTap: viewModel.currentMachine != nil ? {
                        beginAddChocolateBoxFlow()
                    } : nil,
                    onToggleFreshTap: viewModel.currentPickItem != nil ? {
                        if let pickItem = viewModel.currentPickItem {
                            Task {
                                await viewModel.toggleFreshStatus(pickItem)
                            }
                        }
                    } : nil,
                    onChangeInputFieldTap: viewModel.currentPickItem != nil ? {
                        if let pickItem = viewModel.currentPickItem {
                            viewModel.selectedPickItemForCountPointer = pickItem
                            viewModel.showingCountPointerSheet = true
                        }
                    } : nil
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, layout == .stacked ? 12 : 5)
        .padding(.vertical, 8)
    }

    private func layoutMode(for size: CGSize) -> PackingSessionInstructionLayout {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .wide
        }
        if size.width > size.height {
            return .wide
        }
        return .stacked
    }

    private func progressInfo(for command: AudioCommandsResponse.AudioCommand) -> PackingInstructionProgress {
        if viewModel.machineCompletionInfo != nil && command.type == "item" {
            return PackingInstructionProgress(title: "Machine Progress", value: 1)
        }
        switch command.type {
        case "item":
            let identifier = machineIdentifier(for: command)
            let items = viewModel.audioCommands.filter { $0.type == "item" && machineIdentifier(for: $0) == identifier }
            guard !items.isEmpty else {
                return PackingInstructionProgress(title: "Machine Progress", value: 0)
            }
            let completedCount = items.filter { isItemCommandCompleted($0) }.count
            let progress = Double(completedCount) / Double(items.count)
            return PackingInstructionProgress(title: "Machine Progress", value: min(max(progress, 0), 1))
        case "machine":
            let identifier = locationIdentifier(for: command)
            let machines = viewModel.audioCommands.filter { $0.type == "machine" && locationIdentifier(for: $0) == identifier }
            guard !machines.isEmpty else {
                return PackingInstructionProgress(title: "Location Progress", value: 0)
            }
            let completedMachines = machines.filter { isMachineCompleted($0) }.count
            let progress = Double(completedMachines) / Double(machines.count)
            return PackingInstructionProgress(title: "Location Progress", value: min(max(progress, 0), 1))
        case "location":
            let locations = viewModel.audioCommands.filter { $0.type == "location" }
            guard !locations.isEmpty else {
                return PackingInstructionProgress(title: "Run Progress", value: 0)
            }
            let completedLocations = locations.filter { isLocationCompleted($0) }.count
            let progress = Double(completedLocations) / Double(locations.count)
            return PackingInstructionProgress(title: "Run Progress", value: min(max(progress, 0), 1))
        default:
            return PackingInstructionProgress(title: "Progress", value: viewModel.progress)
        }
    }

    private func locationIdentifier(for command: AudioCommandsResponse.AudioCommand) -> String {
        if let id = command.locationId, !id.isEmpty {
            return id
        }
        if let name = command.locationName, !name.isEmpty {
            return name
        }
        return "__unknown-location-\(command.id)__"
    }

    private func machineIdentifier(for command: AudioCommandsResponse.AudioCommand) -> String {
        if let id = command.machineId, !id.isEmpty {
            return id
        }
        if let code = command.machineName, !code.isEmpty {
            return code
        }
        if let code = command.machineCode, !code.isEmpty {
            return code
        }
        return "__unknown-machine-\(command.id)__"
    }

    private func isItemCommandCompleted(_ command: AudioCommandsResponse.AudioCommand) -> Bool {
        guard command.type == "item" else { return false }
        return command.pickEntryIds.allSatisfy(viewModel.completedItems.contains)
    }

    private func isMachineCompleted(_ command: AudioCommandsResponse.AudioCommand) -> Bool {
        let identifier = machineIdentifier(for: command)
        let items = viewModel.audioCommands.filter { $0.type == "item" && machineIdentifier(for: $0) == identifier }
        guard !items.isEmpty else { return false }
        return items.allSatisfy { isItemCommandCompleted($0) }
    }

    private func isLocationCompleted(_ command: AudioCommandsResponse.AudioCommand) -> Bool {
        let identifier = locationIdentifier(for: command)
        let machines = viewModel.audioCommands.filter { $0.type == "machine" && locationIdentifier(for: $0) == identifier }
        guard !machines.isEmpty else { return false }
        return machines.allSatisfy { isMachineCompleted($0) }
    }

    private func beginAddChocolateBoxFlow() {
        guard let machine = viewModel.currentMachine else { return }
        targetMachineForChocolateBox = machine
        chocolateBoxNumberInput = ""
        chocolateBoxErrorMessage = nil
        showingAddChocolateBoxAlert = true
    }
    
    private func submitChocolateBoxEntry() {
        guard let machine = targetMachineForChocolateBox else {
            chocolateBoxErrorMessage = "Unable to determine machine for this chocolate box."
            showingAddChocolateBoxAlert = true
            return
        }
        let trimmedNumber = chocolateBoxNumberInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(trimmedNumber), number > 0 else {
            chocolateBoxErrorMessage = "Enter a valid chocolate box number."
            showingAddChocolateBoxAlert = true
            return
        }
        chocolateBoxErrorMessage = nil
        isCreatingChocolateBox = true
        Task {
            do {
                try await viewModel.createChocolateBox(number: number, machineId: machine.id)
                await MainActor.run {
                    isCreatingChocolateBox = false
                    showingAddChocolateBoxAlert = false
                    chocolateBoxNumberInput = ""
                    targetMachineForChocolateBox = nil
                }
            } catch {
                await MainActor.run {
                    chocolateBoxErrorMessage = error.localizedDescription
                    isCreatingChocolateBox = false
                    showingAddChocolateBoxAlert = true
                }
            }
        }
    }
    
    private var chocolateBoxNumbersForCurrentMachine: [Int] {
        guard let machineId = viewModel.currentMachine?.id else { return [] }
        return viewModel.chocolateBoxes
            .filter { $0.machine?.id == machineId }
            .map { $0.number }
            .sorted()
    }
}



fileprivate struct CurrentCommandView: View {
    let layout: PackingSessionInstructionLayout
    let command: AudioCommandsResponse.AudioCommand
    let machineCompletionInfo: MachineCompletionInfo?
    let skuType: String?
    let progressInfo: PackingInstructionProgress
    let chocolateBoxNumbers: [Int]
    let isFreshOrFrozen: Bool
    let canAddChocolateBox: Bool
    let canToggleFreshStatus: Bool
    let onAddChocolateBoxTap: (() -> Void)?
    let onToggleFreshTap: (() -> Void)?
    let onChangeInputFieldTap: (() -> Void)?

    private var coilCount: Int {
        if let codes = command.coilCodes, !codes.isEmpty {
            return codes.count
        }
        if let coilCode = command.coilCode, !coilCode.isEmpty {
            return 1
        }
        return 0
    }

    private var coilSummary: String? {
        guard coilCount > 0 else { return nil }
        let suffix = coilCount == 1 ? "Coil" : "Coils"
        return "\(coilCount) \(suffix)"
    }

    private var primaryTitle: String {
        switch command.type {
        case "machine":
            if let description = command.machineDescription, !description.isEmpty {
                return description
            }
            return command.machineName ?? "Machine"
        case "location":
            return command.locationName ?? "Location"
        default:
            return command.skuName ?? "Item"
        }
    }

    private var secondaryTitle: String? {
        switch command.type {
        case "machine":
            return command.machineCode ?? command.machineName
        case "location":
            return command.locationAddress ?? command.locationName
        default:
            if let skuType, !skuType.isEmpty {
                return skuType
            }
            return command.skuCode
        }
    }

    private var tertiaryTitle: String? {
        switch command.type {
        case "machine":
            return command.machineTypeName
        case "location":
            return nil
        default:
            return coilSummary
        }
    }

    private var detailMachineText: String? {
        guard command.type == "item" else { return nil }
        if let description = command.machineDescription, !description.isEmpty {
            return description
        }
        return command.machineName
    }

    private var detailLocationText: String? {
        guard command.type == "item" else { return nil }
        return command.locationName
    }

    private var countText: String {
        "\(max(command.count, 0))"
    }

    private var chocolateBoxSummary: String {
        chocolateBoxNumbers.sorted().map(String.init).joined(separator: ", ")
    }

    private func completionDetailText(for info: MachineCompletionInfo) -> String? {
        var parts: [String] = []
        if let description = info.machineDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            parts.append(description)
        }
        if let code = info.machineCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !code.isEmpty {
            parts.append("Code \(code)")
        } else if let name = info.machineName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty {
            parts.append(name)
        }
        if let location = info.locationName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty {
            parts.append(location)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }

    private var shouldDisableAccessoryButtons: Bool {
        machineCompletionInfo != nil
    }

    private var freshChestButtonTitle: String {
        isFreshOrFrozen ? "Remove Fresh" : "Add to Fresh"
    }

    private var freshChestButtonTint: Color {
        Theme.freshChestTint
    }

    private var progressCard: some View {
        ProgressSummaryCard(progressInfo: progressInfo)
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = machineCompletionInfo {
                Text("Machine complete")
                    .font(.title.bold())
                Text(info.message)
                    .font(.title3.weight(.semibold))
                    .lineLimit(4)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Text(primaryTitle)
                    .font(.title.bold())
                    .multilineTextAlignment(.leading)
                if let secondaryTitle, !secondaryTitle.isEmpty {
                    Text(secondaryTitle)
                        .font(.title3.bold())
                }
                if let tertiaryTitle, !tertiaryTitle.isEmpty {
                    Text(tertiaryTitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let machineLine = detailMachineText, !machineLine.isEmpty {
                    Text(machineLine)
                        .font(.headline)
                }
                if let locationLine = detailLocationText, !locationLine.isEmpty {
                    Text(locationLine)
                        .font(.headline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var countCard: some View {
        let isItem = command.type == "item"
        return VStack(spacing: 6) {
            Text(countText)
                .font(.system(size: 96, weight: .black, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .opacity(isItem ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var chocolateBoxCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Chocolate Box")
                .foregroundStyle(.secondary)
                .font(.caption2.bold())
                .padding(.leading, 8)
            Text(chocolateBoxSummary.isEmpty ? "None for this machine" : chocolateBoxSummary)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
    
    private var wideChocolateBoxCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Chocolate Box")
                .foregroundStyle(.secondary)
                .font(.caption2.bold())
                .padding(.leading, 8)
            Text(chocolateBoxSummary.isEmpty ? "None for this machine" : chocolateBoxSummary)
                .font(.headline)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }


    private var freshChestButton: some View {
        Button {
            onToggleFreshTap?()
        } label: {
            Label(freshChestButtonTitle, systemImage: "leaf.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(freshChestButtonTint)
        .disabled(onToggleFreshTap == nil || !canToggleFreshStatus || shouldDisableAccessoryButtons)
    }

    private var addChocolateBoxButton: some View {
        Button {
            onAddChocolateBoxTap?()
        } label: {
            Text("Add Chocolate Box")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(onAddChocolateBoxTap == nil || !canAddChocolateBox || shouldDisableAccessoryButtons)
    }

    private var changeInputFieldButton: some View {
        Button {
            onChangeInputFieldTap?()
        } label: {
            Label("Input Field", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.gray)
        .disabled(onChangeInputFieldTap == nil)
    }

    @ViewBuilder
    private var actionsView: some View {
        if layout == .stacked {
            HStack(spacing: 8) {
                addChocolateBoxButton
                freshChestButton
            }
        } else {
            VStack(spacing: 8) {
                addChocolateBoxButton
                freshChestButton
            }
        }
    }

    var body: some View {
        Group {
            switch layout {
            case .stacked:
                VStack(spacing: 12) {
                    progressCard
                    countCard
                    detailCard
                    chocolateBoxCard
                    actionsView
                }
            case .wide:
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 12) {
                        freshChestButton
                        wideChocolateBoxCard
                        addChocolateBoxButton
                    }
                    .frame(maxWidth: 260)
                    detailCard
                    VStack(spacing: 12) {
                        countCard
                        progressCard
                    }
                    .frame(maxWidth: 220)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chocolateBoxNumbers)
    }
}


fileprivate struct ProgressSummaryCard: View {
    let progressInfo: PackingInstructionProgress

    private var clampedValue: Double {
        min(max(progressInfo.value, 0), 1)
    }

    private var percentageText: String {
        let percent = Int((clampedValue * 100).rounded())
        return "\(percent)%"
    }

    var body: some View {
        HStack(spacing: 12) {
            ProgressDonutView(value: clampedValue)
            VStack(alignment: .leading, spacing: 2) {
                Text(progressInfo.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(percentageText)
                    .font(.title3.bold())
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemFill))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ProgressDonutView: View {
    let value: Double

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(clampedValue))
                .stroke(
                    Color.green,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 48, height: 48)
    }
}

fileprivate struct PackingInstructionProgress {
    let title: String
    let value: Double
}

fileprivate enum PackingSessionInstructionLayout {
    case stacked
    case wide
}

private extension View {
    @ViewBuilder
    func onChangeCompat<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void) -> some View {
        if #available(iOS 17, *) {
            self.onChange(of: value, initial: false) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}

#Preview("Packing Session Sheet") {
    let credentials = AuthCredentials(
        accessToken: "preview-token",
        refreshToken: "preview-refresh",
        userID: "user-1",
        expiresAt: Date().addingTimeInterval(3600)
    )
    let profile = UserProfile(
        id: "user-1",
        email: "jordan@example.com",
        firstName: "Jordan",
        lastName: "Smith",
        phone: nil,
        role: "PICKER"
    )
    let session = AuthSession(credentials: credentials, profile: profile)
    
    return PackingSessionSheet(runId: "run-12345", packingSessionId: "preview-packing-session", session: session, service: PreviewRunsService())
}
