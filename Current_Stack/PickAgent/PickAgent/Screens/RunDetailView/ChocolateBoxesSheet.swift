//
//  ChocolateBoxesSheet.swift
//  PickAgent
//
//  Created by Logan Janssen on 11/5/2025.
//

import SwiftUI

struct ChocolateBoxesSheet: View {
    @ObservedObject var viewModel: RunDetailViewModel
    let locationMachines: [RunDetail.Machine]
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddBoxSheet = false
    
    private var locationChocolateBoxes: [RunDetail.ChocolateBox] {
        let locationMachineIds = Set(locationMachines.map { $0.id })
        return viewModel.chocolateBoxes.filter { box in
            box.machine?.id != nil && locationMachineIds.contains(box.machine!.id)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if locationChocolateBoxes.isEmpty {
                    ContentUnavailableView(
                        "No Chocolate Boxes",
                        systemImage: "shippingbox",
                        description: Text("Add chocolate boxes to track their machine assignments")
                    )
                } else {
                    ForEach(locationChocolateBoxes) { box in
                        ChocolateBoxRow(box: box, viewModel: viewModel)
                    }
                    .onDelete(perform: deleteChocolateBoxes)
                }
            }
            .navigationTitle("Chocolate Boxes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddBoxSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddBoxSheet) {
                AddChocolateBoxSheet(viewModel: viewModel, locationMachines: locationMachines)
            }
        }
    }
    
    private func deleteChocolateBoxes(offsets: IndexSet) {
        for index in offsets {
            let box = locationChocolateBoxes[index]
            Task {
                await viewModel.deleteChocolateBox(boxId: box.id)
            }
        }
    }
}

struct ChocolateBoxRow: View {
    let box: RunDetail.ChocolateBox
    @ObservedObject var viewModel: RunDetailViewModel
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                
                if let machine = box.machine {
                    
                    HStack(spacing: 4) {
                        if let description = machine.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(description)
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        Text(machine.code)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .fontWeight(.regular)
                    }
                    
                    if let machineType = machine.machineType {
                        Text(machineType.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                } else {
                    Text("No machine assigned")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Text("Box")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("\(box.number)")
                    .font(.title)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddChocolateBoxSheet: View {
    @ObservedObject var viewModel: RunDetailViewModel
    let locationMachines: [RunDetail.Machine]
    @Environment(\.dismiss) private var dismiss
    
    @State private var boxNumber: String = ""
    @State private var selectedMachineId: String = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    private var isFormValid: Bool {
        !boxNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedMachineId.isEmpty &&
        Int(boxNumber) != nil &&
        Int(boxNumber)! > 0
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Chocolate Box Details") {
                    TextField("Box Number", text: $boxNumber)
                        .keyboardType(.numberPad)
                        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in
                            // Remove any non-numeric characters
                            boxNumber = boxNumber.filter { $0.isNumber }
                        }
                }
                
                Section("Machine Assignment") {
                    if locationMachines.isEmpty {
                        Text("No machines available for this location")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        Picker("Machine", selection: $selectedMachineId) {
                            Text("Select a machine").tag("")
                            ForEach(locationMachines) { machine in
                                HStack {
                                    Text(machine.code)
                                    Spacer()
                                    if let description = machine.description {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(machine.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Chocolate Box")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addChocolateBox()
                    }
                    .disabled(!isFormValid || isCreating)
                }
            }
            .disabled(isCreating)
            .overlay {
                if isCreating {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).opacity(0.8))
                }
            }
        }
        .onAppear {
            boxNumber = ""
            selectedMachineId = ""
            errorMessage = nil
        }
    }
    
    private func addChocolateBox() {
        guard let number = Int(boxNumber.trimmingCharacters(in: .whitespacesAndNewlines)),
              number > 0 else {
            errorMessage = "Please enter a valid box number"
            return
        }
        
        guard !selectedMachineId.isEmpty else {
            errorMessage = "Please select a machine"
            return
        }
        
        isCreating = true
        errorMessage = nil
        
        Task {
            await viewModel.createChocolateBox(number: number, machineId: selectedMachineId)
            
            await MainActor.run {
                isCreating = false
                if viewModel.errorMessage == nil {
                    dismiss()
                } else {
                    errorMessage = viewModel.errorMessage
                }
            }
        }
    }
}



#Preview("Chocolate Box Row - With Machine") {
    let downtown = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
    let snackType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
    let machineA = RunDetail.Machine(id: "machine-1", code: "A-101", description: "Lobby", machineType: snackType, location: downtown)
    let chocolateBox = RunDetail.ChocolateBox(id: "box-1", number: 1, machine: machineA)
    
    return ChocolateBoxRow(box: chocolateBox, viewModel: RunDetailViewModel(runId: "run-12345", session: AuthSession(credentials: AuthCredentials(accessToken: "token", refreshToken: "refresh", userID: "user-1", expiresAt: Date().addingTimeInterval(3600)), profile: UserProfile(id: "user-1", email: "test@example.com", firstName: "Test", lastName: "User", phone: nil, role: "PICKER")), service: PreviewRunsService()))
}

#Preview("Chocolate Box Row - No Machine") {
    let chocolateBox = RunDetail.ChocolateBox(id: "box-2", number: 5, machine: nil)
    
    return ChocolateBoxRow(box: chocolateBox, viewModel: RunDetailViewModel(runId: "run-12345", session: AuthSession(credentials: AuthCredentials(accessToken: "token", refreshToken: "refresh", userID: "user-1", expiresAt: Date().addingTimeInterval(3600)), profile: UserProfile(id: "user-1", email: "test@example.com", firstName: "Test", lastName: "User", phone: nil, role: "PICKER")), service: PreviewRunsService()))
}

#Preview("Chocolate Boxes Sheet") {
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
    
    let viewModel = RunDetailViewModel(runId: "run-12345", session: session, service: PreviewRunsService())
    
    // Load the preview data to get the actual machines and chocolate boxes
    let downtown = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
    let snackType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
    let drinkType = RunDetail.MachineTypeDescriptor(id: "type-2", name: "Drink Machine", description: "Cold beverages")
    let machineA = RunDetail.Machine(id: "machine-1", code: "A-101", description: "Lobby", machineType: snackType, location: downtown)
    let machineB = RunDetail.Machine(id: "machine-2", code: "B-204", description: "Breakroom", machineType: drinkType, location: downtown)
    let machineC = RunDetail.Machine(id: "machine-3", code: "C-08", description: "Front Vestibule", machineType: drinkType, location: downtown)
    let locationMachines = [machineA, machineB, machineC]
    
    return NavigationStack {
        ChocolateBoxesSheet(viewModel: viewModel, locationMachines: locationMachines)
    }
}
