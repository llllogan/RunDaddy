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
                // Progress Header
                VStack(spacing: 8) {
                    HStack {
                        Text("Packing Session")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button("Done") {
                            viewModel.stopSession()
                            dismiss()
                        }
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .buttonStyle(.bordered)
                    }
                    
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
                    .background(Color(.systemGray6))
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
                    .background(Color(.systemGray6))
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
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                
                Spacer()
                
                // Control Buttons
                if !viewModel.isLoading && !viewModel.isSessionComplete {
                    HStack(spacing: 16) {
                        Button {
                            Task {
                                await viewModel.goBack()
                            }
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.title2)
                        }
                        .buttonStyle(CircularButtonStyle())
                        .disabled(!viewModel.canGoBack || viewModel.isSpeaking)
                        
                        Button {
                            Task {
                                await viewModel.repeatCurrent()
                            }
                        } label: {
                            Image(systemName: "repeat")
                                .font(.title2)
                        }
                        .buttonStyle(CircularButtonStyle())
                        .disabled(viewModel.currentCommand == nil || viewModel.isSpeaking)
                        
                        Button {
                            Task {
                                await viewModel.skipCurrent()
                            }
                        } label: {
                            Image(systemName: "forward.frame.fill")
                                .font(.title2)
                        }
                        .buttonStyle(CircularButtonStyle())
                        .disabled(viewModel.isSessionComplete || viewModel.isSpeaking)
                        
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
                                .font(.title2)
                        }
                        .buttonStyle(CircularButtonStyle(primary: true))
                        .tint(viewModel.isSessionComplete ? .green : .blue)
                        .disabled(viewModel.isSpeaking)
                    }
                    .padding()
                }
            }
            .padding()
            .navigationBarHidden(true)
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
            // Command Type Header
            HStack {
                Text(command.type == "machine" ? "🏭 Machine" : "📦 Item")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Group {
                            if command.type == "machine" {
                                LinearGradient(
                                    colors: [Color.orange, Color.orange.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            } else {
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                        }
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: command.type == "machine" ? .orange.opacity(0.3) : .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                
                Spacer()
                
                if isSpeaking {
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue.gradient)
                                .frame(width: 4, height: 20)
                                .scaleEffect(isSpeaking ? 1.0 : 0.5, anchor: .bottom)
                                .animation(
                                    .easeInOut(duration: 0.8)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.15),
                                    value: isSpeaking
                                )
                        }
                    }
                    .frame(height: 20)
                }
            }
            
            // Command Content
            if command.type == "machine" {
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
                    
                    if let coilCode = command.coilCode, !coilCode.isEmpty {
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
        }
        .padding()
        .background(Color(.systemBackground))
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