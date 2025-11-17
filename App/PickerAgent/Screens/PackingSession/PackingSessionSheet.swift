//
//  PackingSessionSheet.swift
//  PickAgent
//
//  Created by Logan Janssen on 11/6/2025.
//

import SwiftUI
import AVFoundation

struct PackingSessionSheet: View {
    let runId: String
    let session: AuthSession
    @StateObject private var viewModel: PackingSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddChocolateBoxSheet = false
    @State private var chocolateBoxNumberInput = ""
    @State private var chocolateBoxErrorMessage: String?
    @State private var isCreatingChocolateBox = false
    @State private var targetMachineForChocolateBox: RunDetail.Machine?
    
    init(runId: String, session: AuthSession, service: RunsServicing = RunsService()) {
        self.runId = runId
        self.session = session
        _viewModel = StateObject(wrappedValue: PackingSessionViewModel(runId: runId, session: session, service: service))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                
                // Current Command Display
                if viewModel.isSessionComplete {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.green)
                        Text("All items packed")
                            .font(.title3)
                            .fontWeight(.semibold)
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
                    CommandDebugLogger(
                        command: command,
                        machines: viewModel.runDetail?.machines,
                        resolvedLocation: viewModel.currentLocationName
                    )
                    CurrentCommandView(
                        command: command,
                        isSpeaking: viewModel.isSpeaking,
                        skuType: viewModel.currentPickItem?.sku?.type,
                        machineDescription: viewModel.currentMachine?.description,
                        machineCode: viewModel.currentMachine?.code,
                        locationName: viewModel.currentLocationName,
                        canAddChocolateBox: command.type == "item" && viewModel.currentMachine != nil,
                        chocolateBoxNumbers: chocolateBoxNumbersForCurrentMachine,
                        onAddChocolateBoxTap: {
                            beginAddChocolateBoxFlow()
                        }
                        )
                } else if viewModel.isLoading {
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
                            .font(.headline)
                            .fontWeight(.semibold)
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
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stop Packing", systemImage: "stop.fill") {
                        viewModel.stopSession()
                        dismiss()
                    }
                    .tint(.red)
                }
                
                ToolbarItemGroup(placement: .bottomBar) {
                    Menu("More Options", systemImage: "ellipsis") {
                        Button {
                            if let pickItem = viewModel.currentPickItem {
                                Task {
                                    await viewModel.toggleCheeseStatus(pickItem)
                                }
                            }
                        } label: {
                            Label("Cheese Tub", systemImage: viewModel.currentPickItem?.sku?.isCheeseAndCrackers == true ? "minus.circle.fill" : "plus.circle.fill")
                        }
                        .disabled(viewModel.currentPickItem == nil || viewModel.isSpeaking)
                        
                        Button {
                            if let pickItem = viewModel.currentPickItem {
                                viewModel.selectedPickItemForCountPointer = pickItem
                                viewModel.showingCountPointerSheet = true
                            }
                        } label: {
                            Label("Change Input Field", systemImage: "square.and.pencil")
                        }
                        .disabled(viewModel.currentPickItem == nil || viewModel.isSpeaking)
                    }
                    
                    Spacer()
                    
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
                                viewModel.stopSession()
                                dismiss()
                            } else {
                                await viewModel.goForward()
                            }
                        }
                    } label: {
                        Image(systemName: viewModel.isSessionComplete ? "checkmark.circle.fill" : "forward.fill")
                    }
                    .tint(viewModel.isSessionComplete ? .green : .blue)
                    .disabled(viewModel.isSpeaking)
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
                    viewModel: RunDetailViewModel(runId: runId, session: session, service: viewModel.service)
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingAddChocolateBoxSheet, onDismiss: {
            chocolateBoxNumberInput = ""
            chocolateBoxErrorMessage = nil
            targetMachineForChocolateBox = nil
        }) {
            if let machine = targetMachineForChocolateBox {
                ChocolateBoxNumberPadSheet(
                    machineDescription: machine.description,
                    machineCode: machine.code,
                    numberText: $chocolateBoxNumberInput,
                    isSubmitting: isCreatingChocolateBox,
                    errorMessage: chocolateBoxErrorMessage,
                    onCancel: {
                        showingAddChocolateBoxSheet = false
                        targetMachineForChocolateBox = nil
                    },
                    onSave: submitChocolateBoxEntry
                )
                .presentationDetents([.fraction(0.35), .medium])
                .presentationDragIndicator(.visible)
            }
        }

        .onAppear {
            Task {
                await viewModel.loadAudioCommands()
            }
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }

    private func beginAddChocolateBoxFlow() {
        guard let machine = viewModel.currentMachine else { return }
        targetMachineForChocolateBox = machine
        chocolateBoxNumberInput = ""
        chocolateBoxErrorMessage = nil
        showingAddChocolateBoxSheet = true
    }
    
    private func submitChocolateBoxEntry() {
        guard let machine = targetMachineForChocolateBox else {
            chocolateBoxErrorMessage = "Unable to determine machine for this chocolate box."
            return
        }
        let trimmedNumber = chocolateBoxNumberInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(trimmedNumber), number > 0 else {
            chocolateBoxErrorMessage = "Enter a valid chocolate box number."
            return
        }
        chocolateBoxErrorMessage = nil
        isCreatingChocolateBox = true
        Task {
            do {
                try await viewModel.createChocolateBox(number: number, machineId: machine.id)
                await MainActor.run {
                    isCreatingChocolateBox = false
                    showingAddChocolateBoxSheet = false
                    targetMachineForChocolateBox = nil
                }
            } catch {
                await MainActor.run {
                    chocolateBoxErrorMessage = error.localizedDescription
                    isCreatingChocolateBox = false
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

struct CurrentCommandView: View {
    let command: AudioCommandsResponse.AudioCommand
    let isSpeaking: Bool
    let skuType: String?
    let machineDescription: String?
    let machineCode: String?
    let locationName: String?
    let canAddChocolateBox: Bool
    let chocolateBoxNumbers: [Int]
    let onAddChocolateBoxTap: (() -> Void)?

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
        let suffix = coilCount == 1 ? "coil" : "coils"
        return "\(coilCount) \(suffix)"
    }

    private var machineDisplayText: String? {
        let hasDescription = !(machineDescription?.isEmpty ?? true)
        let hasCode = !(machineCode?.isEmpty ?? true)

        switch (hasDescription, hasCode) {
        case (true, true):
            return "\(machineDescription!) • \(machineCode!)"
        case (true, false):
            return machineDescription
        case (false, true):
            return machineCode
        default:
            return nil
        }
    }
    
    private var shouldShowActionCards: Bool {
        (!chocolateBoxNumbers.isEmpty) || (canAddChocolateBox && onAddChocolateBoxTap != nil)
    }

    var body: some View {
        if command.type == "location" {
            VStack(alignment: .leading, spacing: 8) {
                Text(command.locationName ?? "Unknown Location")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Theme.packingSessionBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        } else if command.type == "machine" {
            VStack(alignment: .leading, spacing: 8) {
                Text(command.machineName ?? "Unknown Machine")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Theme.packingSessionBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        } else {
            HStack(alignment: .top, spacing: 20) {
                if shouldShowActionCards {
                    VStack(spacing: 12) {
                        if !chocolateBoxNumbers.isEmpty {
                            ChocolateBoxNumbersActionCard(
                                machineDetails: machineDisplayText,
                                chocolateBoxNumbers: chocolateBoxNumbers
                            )
                        }
                        if canAddChocolateBox, let onAddChocolateBoxTap {
                            AddChocolateBoxActionCard(
                                machineDetails: machineDisplayText,
                                action: onAddChocolateBoxTap
                            )
                        }
                    }
                    .frame(maxWidth: 240)
                }
                PackingItemDetailCard(
                    command: command,
                    skuType: skuType,
                    machineDisplayText: machineDisplayText,
                    locationDisplayText: locationName,
                    coilSummary: coilSummary
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CircularButtonStyle: ButtonStyle {
    let primary: Bool
    
    init(primary: Bool = false) {
        self.primary = primary
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 56, height: 56)
            .background(
                Group {
                    if primary {
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        Color(.systemGray5)
                    }
                }
            )
            .foregroundColor(primary ? .white : .primary)
            .clipShape(Circle())
            .shadow(color: primary ? .blue.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.bouncy(duration: 0.3), value: configuration.isPressed)
    }
}

struct AddChocolateBoxActionCard: View {
    let machineDetails: String?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.brown)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.2))
                        )
                    Text("Add chocolate box")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.42, green: 0.24, blue: 0.12), Color(red: 0.29, green: 0.16, blue: 0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add chocolate box")
    }
}

struct ChocolateBoxNumbersActionCard: View {
    let machineDetails: String?
    let chocolateBoxNumbers: [Int]
    
    private var sortedNumbers: [Int] {
        chocolateBoxNumbers.sorted()
    }
    
    private let numberColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.2))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chocolate boxes")
                        .font(.headline.weight(.semibold))
                    if let machineDetails, !machineDetails.isEmpty {
                        Text(machineDetails)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
            }
            
            LazyVGrid(columns: numberColumns, alignment: .leading, spacing: 2) {
                ForEach(sortedNumbers, id: \.self) { number in
                    Text("#\(number)")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                        .accessibilityLabel("Chocolate box number \(number)")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.packingSessionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}

struct PackingItemDetailCard: View {
    let command: AudioCommandsResponse.AudioCommand
    let skuType: String?
    let machineDisplayText: String?
    let locationDisplayText: String?
    let coilSummary: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(command.skuName ?? "Unknown Item")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if let skuType, !skuType.isEmpty {
                        Text(skuType)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(command.count)")
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    
                    if let coilSummary {
                        Text(coilSummary)
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let locationDisplayText, !locationDisplayText.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(locationDisplayText)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    if let machineDisplayText {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Machine")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(machineDisplayText)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.packingSessionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

struct ChocolateBoxNumberPadSheet: View {
    let machineDescription: String?
    let machineCode: String?
    @Binding var numberText: String
    let isSubmitting: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void
    @FocusState private var isNumberFieldFocused: Bool
    
    private var machineSummary: String {
        if let description = machineDescription, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let code = machineCode, !code.isEmpty {
                return "\(description) • \(code)"
            }
            return description
        }
        return machineCode ?? "Assigned machine"
    }
    
    private var isFormValid: Bool {
        guard let value = Int(numberText), value > 0 else { return false }
        return true
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Machine")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(machineSummary)
                            .font(.headline)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chocolate box number")
                            .font(.subheadline.weight(.semibold))
                        TextField("Enter number", text: $numberText)
                            .keyboardType(.numberPad)
                            .focused($isNumberFieldFocused)
                            .padding(.vertical, 8)
                            .font(.title2.weight(.medium))
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .onChangeCompat(of: numberText) { newValue in
                        numberText = newValue.filter { $0.isNumber }
                    }
                    
                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Chocolate Box")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onSave()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Add")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!isFormValid || isSubmitting)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isNumberFieldFocused = true
            }
        }
    }
}

#Preview("Chocolate Box Number Pad Sheet") {
    ChocolateBoxNumberPadSheet(
        machineDescription: "Lobby",
        machineCode: "A-101",
        numberText: .constant("12"),
        isSubmitting: false,
        errorMessage: "This box already exists",
        onCancel: {},
        onSave: {}
    )
}

struct CommandDebugLogger: View {
    init(command: AudioCommandsResponse.AudioCommand, machines: [RunDetail.Machine]?, resolvedLocation: String?) {
        print("🍫 Command type: \(command.type) machineId: \(command.machineId ?? "nil") pickEntryIds: \(command.pickEntryIds)")
        if let machines {
            print("🍫 Loaded machines: \(machines.map { $0.id })")
        } else {
            print("🍫 Run detail machines not loaded")
        }
        let commandLocation = (command.locationName ?? "nil").isEmpty ? "empty" : (command.locationName ?? "nil")
        print("🍫 Command locationName: \(commandLocation) | resolved location: \(resolvedLocation ?? "nil")")
    }
    
    var body: some View {
        EmptyView()
    }
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
    
    return PackingSessionSheet(runId: "run-12345", session: session, service: PreviewRunsService())
}
