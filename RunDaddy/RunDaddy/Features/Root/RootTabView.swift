//
//  RootTabView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    @EnvironmentObject private var sessionController: PackingSessionController
    var onLogout: () -> Void

    var body: some View {
        TabView {
            RunHistoryView()
                .tabItem {
                    Label("Runs", systemImage: "figure.run")
                }

            MachinesView()
                .tabItem {
                    Label("Info", systemImage: "info.circle")
                }

            SettingsView(onLogout: onLogout)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tabViewStyle(.automatic)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            if sessionController.hasActiveSession {
                PackingSessionBar()
            } else {
                Text("Not currently packing")
            }
        }
        .sheet(isPresented: $sessionController.isSheetPresented,
               onDismiss: { sessionController.minimizeSession() }) {
            Group {
                if let viewModel = sessionController.activeViewModel {
                    PackingSessionView(viewModel: viewModel, controller: sessionController)
                } else {
                    EmptyView()
                }
            }
            .sheet(isPresented: $sessionController.isSheetPresented,
                   onDismiss: { sessionController.minimizeSession() }) {
                Group {
                    if let viewModel = sessionController.activeViewModel {
                        PackingSessionView(viewModel: viewModel, controller: sessionController)
                    } else {
                        EmptyView()
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
    }
}

struct PackingSessionBar: View {
    @EnvironmentObject private var sessionController: PackingSessionController
    @Environment(\.haptics) private var haptics

    private var viewModel: PackingSessionViewModel? {
        sessionController.activeViewModel
    }

    var body: some View {
        if let viewModel {
            HStack(spacing: 16) {
                Button {
                    haptics.secondaryButtonTap()
                    sessionController.expandSession()
                } label: {
                    PackingSessionSummaryView(viewModel: viewModel)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(summaryAccessibilityLabel(for: viewModel))

                Spacer(minLength: 0)

                Button {
                    haptics.secondaryButtonTap()
                    sessionController.repeatActiveSession()
                } label: {
                    Label("Repeat", systemImage: "arrow.uturn.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)

                Button {
                    if viewModel.isSessionComplete {
                        haptics.success()
                    } else {
                        haptics.prominentActionTap()
                    }
                    sessionController.advanceActiveSession()
                } label: {
                    Label("Next", systemImage: "forward")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isSessionComplete ? .green : .accentColor)
                .disabled(!viewModel.isSessionComplete && !viewModel.hasActiveStep)
            }
            .frame(maxWidth: .infinity)
        } else {
            EmptyView()
        }
    }

    private func summaryAccessibilityLabel(for viewModel: PackingSessionViewModel) -> String {
        if let descriptor = viewModel.currentItemDescriptor {
            return "Current item \(descriptor.title) on \(descriptor.machine). Tap to open session."
        } else if viewModel.isSessionComplete {
            return "Packing session complete. Tap to review or finish."
        } else if let machine = viewModel.currentMachineDescriptor {
            return "Machine \(machine.name). Tap to open session."
        } else {
            return "Packing session loading. Tap to open session."
        }
    }
}

private struct PackingSessionSummaryView: View {
    @ObservedObject var viewModel: PackingSessionViewModel

    var body: some View {
        HStack(spacing: 16) {
            if let descriptor = viewModel.currentItemDescriptor {
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(descriptor.machine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                VStack(alignment: .center, spacing: 2) {
                    Text("\(descriptor.pick)")
                        .font(.headline)
                        .lineLimit(1)
                    Text("Need")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if viewModel.isSessionComplete {
                Text("Session complete")
                    .font(.headline)
            } else if let machine = viewModel.currentMachineDescriptor {
                VStack(alignment: .leading, spacing: 2) {
                    Text(machine.name)
                        .font(.headline)
                        .lineLimit(1)
                    if let location = machine.location, !location.isEmpty {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("Preparing session…")
                    .font(.headline)
            }
        }
    }
}


#Preview {
    RootTabView(onLogout: {})
        .environmentObject(PackingSessionController())
        .modelContainer(PreviewFixtures.container)
}

#if DEBUG
private struct PackingSessionBarPreview: View {
    @StateObject private var viewModel = PackingSessionViewModel(run: PreviewFixtures.sampleRun)

    var body: some View {
        HStack(spacing: 16) {
            PackingSessionSummaryView(viewModel: viewModel)
            Spacer(minLength: 0)
            Button("Repeat") {}
            Button("Next") {}
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .onAppear {
            viewModel.previewSelectFirstItem()
        }
    }
}

#Preview("Session Bar Variants") {
    PackingSessionBarPreview()
        .modelContainer(PreviewFixtures.container)
}
#endif
