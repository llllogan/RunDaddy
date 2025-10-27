//
//  RunDetailView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftData
import SwiftUI

struct RunDetailView: View {
    @Bindable var run: Run
    @EnvironmentObject private var sessionController: PackingSessionController
    @Environment(\.openURL) private var openURL
    @Environment(\.haptics) private var haptics
    @AppStorage(SettingsKeys.navigationApp) private var navigationAppRawValue: String = NavigationApp.appleMaps.rawValue
    @State private var isPresentingOrderEditor = false
    @State private var isShowingResetRunAlert = false

    private var navigationApp: NavigationApp {
        NavigationApp(rawValue: navigationAppRawValue) ?? .appleMaps
    }

    private var locationSections: [RunLocationSection] {
        RunDetailSectionsBuilder.locationSections(for: run)
    }

    private var notPackedSections: [NotPackedLocationSection] {
        RunDetailSectionsBuilder.notPackedSections(for: run)
    }

    private var notPackedCount: Int {
        notPackedSections.reduce(into: 0) { $0 += $1.items.count }
    }

    private var locationCount: Int {
        locationSections.count
    }

    private var machineCount: Int {
        locationSections.reduce(into: 0) { $0 += $1.machineCount }
    }

    private var totalCoils: Int {
        run.runCoils.count
    }

    private var packedCount: Int {
        run.runCoils.filter(\.packed).count
    }

    private var hasPackedItems: Bool {
        run.runCoils.contains(where: \.packed)
    }

    private var navigationTitle: String {
        run.date.formatted(.dateTime.day().month().year())
    }

    var body: some View {
        List {
            Section {
                RunOverviewBento(run: run,
                                 locationSections: locationSections,
                                 machineCount: machineCount,
                                 totalCoils: totalCoils,
                                 packedCount: packedCount,
                                 notPackedCount: notPackedCount)
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                Text("Run Overview")
            }

            Section {
                if locationSections.isEmpty {
                    Text("No locations were imported for this run.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(locationSections) { section in
                        NavigationLink {
                            RunLocationDetailView(run: run, section: section)
                        } label: {
                            RunLocationRow(section: section)
                        }
                    }
                }
            } header: {
                LocationsSectionHeader(locationCount: locationSections.count)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    haptics.prominentActionTap()
                    sessionController.beginSession(for: run)
                } label: {
                    Label("Start packing", systemImage: "tray")
                }
                .disabled(run.runCoils.isEmpty)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(locationSections) { section in
                        Button {
                            openDirections(to: section.location)
                        } label: {
                            Label(section.location.name, systemImage: "mappin.and.ellipse")
                        }
                        .disabled(mapsURL(for: section.location) == nil)
                    }
                } label: {
                    Label("Directions", systemImage: "map")
                }
                .disabled(locationSections.isEmpty)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        sessionController.beginSession(for: run)
                    } label: {
                        Label("Start packing", systemImage: "tray")
                    }
                    .disabled(run.runCoils.isEmpty)

                    Button {
                        isPresentingOrderEditor = true
                    } label: {
                        Label("Reorder locations", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(locationSections.count <= 1)

                    Divider()

                    Menu {
                        ForEach(locationSections) { section in
                            Button {
                                openDirections(to: section.location)
                            } label: {
                                Label(section.location.name, systemImage: "mappin.and.ellipse")
                            }
                            .disabled(mapsURL(for: section.location) == nil)
                        }
                    } label: {
                        Label("Directions", systemImage: "map")
                    }
                    .disabled(locationSections.isEmpty)
                    
                    Divider()
                    
                    Button {
                        isShowingResetRunAlert = true
                    } label: {
                        Label("Mark all items unpacked", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!hasPackedItems)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Run actions")
            }
        }
        .sheet(isPresented: $isPresentingOrderEditor) {
            let items = locationSections.map { section in
                LocationOrderEditor.Item(id: section.id,
                                         name: section.location.name,
                                         packOrder: section.packOrder)
            }
            LocationOrderEditor(items: items) { updatedItems in
                applyLocationOrder(updatedItems)
            }
        }
        .alert("Reset packing status?", isPresented: $isShowingResetRunAlert) {
            Button("Reset", role: .destructive) {
                haptics.secondaryButtonTap()
                markAllRunItemsAsUnpacked()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to reset the packing status for this run?")
        }
    }

    private func applyLocationOrder(_ items: [LocationOrderEditor.Item]) {
        let orderMap = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset + 1) })

        withAnimation {
            for runCoil in run.runCoils {
                guard let locationID = runCoil.coil.machine.location?.id,
                      let newOrder = orderMap[locationID] else {
                    continue
                }
                runCoil.packOrder = Int64(newOrder)
            }

            run.runCoils.sort { lhs, rhs in
                if lhs.packOrder == rhs.packOrder {
                    return lhs.coil.machinePointer.localizedStandardCompare(rhs.coil.machinePointer) == .orderedAscending
                }
                return lhs.packOrder < rhs.packOrder
            }
        }
    }

    private func markAllRunItemsAsUnpacked() {
        guard hasPackedItems else { return }
        withAnimation {
            for runCoil in run.runCoils {
                runCoil.packed = false
            }
        }
    }

    private func openDirections(to location: Location) {
        guard let url = mapsURL(for: location) else { return }
        openURL(url)
    }

    private func mapsURL(for location: Location) -> URL? {
        let trimmedAddress = location.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return nil }

        guard let encodedAddress = trimmedAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        switch navigationApp {
        case .appleMaps:
            return URL(string: "http://maps.apple.com/?q=\(encodedAddress)")
        case .waze:
            return URL(string: "https://www.waze.com/ul?q=\(encodedAddress)&navigate=yes")
        }
    }
}

#Preview {
    NavigationStack {
        RunDetailView(run: PreviewFixtures.sampleRun)
    }
    .environmentObject(PackingSessionController())
    .modelContainer(PreviewFixtures.container)
}

#Preview("Location Detail") {
    NavigationStack {
        if let locationSection = RunDetailSectionsBuilder.locationSections(for: PreviewFixtures.sampleRun).first {
            RunLocationDetailView(run: PreviewFixtures.sampleRun, section: locationSection)
        } else {
            Text("Missing preview data")
        }
    }
    .environmentObject(PackingSessionController())
    .modelContainer(PreviewFixtures.container)
}
