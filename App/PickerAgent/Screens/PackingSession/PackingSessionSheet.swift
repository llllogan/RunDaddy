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
                    CurrentCommandView(command: command, isSpeaking: viewModel.isSpeaking)
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
                
                VStack {
                    
                    HStack {
                        Text("\(viewModel.completedCount) / \(viewModel.totalItems)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(viewModel.progress * 100))%")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .scaleEffect(y: 1.5)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Spacer()
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

        .onAppear {
            Task {
                await viewModel.loadAudioCommands()
            }
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }
}

struct CurrentCommandView: View {
    let command: AudioCommandsResponse.AudioCommand
    let isSpeaking: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            HStack {
                
                // Command Content
                if command.type == "location" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(command.locationName ?? "Unknown Location")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.leading)
                        
                        Text("Navigate to this location to continue packing")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if command.type == "machine" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(command.machineName ?? "Unknown Machine")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.leading)
                        
                        Text("Use the controls below to navigate through items")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(command.skuName ?? "Unknown Item")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.leading)
                        
                        if let skuCode = command.skuCode, !skuCode.isEmpty {
                            Text(skuCode)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let coilCodes = command.coilCodes, !coilCodes.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Coils (\(coilCodes.count))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(coilCodes.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if let coilCode = command.coilCode, !coilCode.isEmpty {
                            Text("Coil \(coilCode)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("NEED")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(command.count)")
                                .font(.system(size: 48, weight: .heavy, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.packingSessionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
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
