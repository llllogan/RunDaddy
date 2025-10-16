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

    var body: some View {
        TabView {
            RunHistoryView()
                .tabItem {
                    Label("Runs", systemImage: "figure.run")
                }

            MachinesView()
                .tabItem {
                    Label("Machines", systemImage: "building")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.xaxis")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tabViewStyle(.automatic)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            if sessionController.hasActiveSession {
                PackingSessionBar()
            }
        }
        .sheet(isPresented: $sessionController.isSheetPresented,
               onDismiss: { sessionController.minimizeSession() }) {
            if let viewModel = sessionController.activeViewModel {
                PackingSessionView(viewModel: viewModel, controller: sessionController)
            } else {
                EmptyView()
            }
        }
    }
}

struct PackingSessionBar: View {
    @EnvironmentObject private var sessionController: PackingSessionController
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var viewModel: PackingSessionViewModel? {
        sessionController.activeViewModel
    }

    var body: some View {
        Group {
            if let viewModel {
                Button {
                    sessionController.expandSession()
                } label: {
                    PackingSessionBarContent(viewModel: viewModel, placement: placement)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open packing session")
            } else {
                EmptyView()
            }
        }
    }
}

private struct PackingSessionBarContent: View {
    @ObservedObject var viewModel: PackingSessionViewModel
    let placement: TabViewBottomAccessoryPlacement?

    var body: some View {
        Group {
            switch placement {
            case .inline:
                expandedContent
            case .expanded:
                expandedContent
            default:
                expandedContent
            }
        }
    }

    private var inlineContent: some View {
        HStack {
            if let descriptor = viewModel.currentItemDescriptor {
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text(descriptor.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(descriptor.machine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    VStack(alignment: .center) {
                        Text("\(descriptor.pick)")
                            .font(.headline)
                            .lineLimit(1)
                        Text("Need")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var expandedContent: some View {
        HStack {
            if let descriptor = viewModel.currentItemDescriptor {
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text(descriptor.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(descriptor.machine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    VStack(alignment: .center) {
                        Text("\(descriptor.pick)")
                            .font(.headline)
                            .lineLimit(1)
                        Text("Need")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 90)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}


#Preview {
    RootTabView()
        .environmentObject(PackingSessionController())
        .modelContainer(PreviewFixtures.container)
}

private struct PackingSessionBarPreview: View {
    @StateObject private var viewModel = PackingSessionViewModel(run: PreviewFixtures.sampleRun)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Inline")
                .font(.caption)
                .foregroundStyle(.secondary)
            PackingSessionBarContent(viewModel: viewModel, placement: .inline)

            Text("Expanded")
                .font(.caption)
                .foregroundStyle(.secondary)
            PackingSessionBarContent(viewModel: viewModel, placement: .expanded)
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
