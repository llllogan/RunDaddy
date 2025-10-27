//
//  RunDetailView.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftData
import SwiftUI

fileprivate struct RunMachineSection: Identifiable {
    let machine: Machine
    let coils: [RunCoil]

    var id: String { machine.id }
    var coilCount: Int { coils.count }
}

fileprivate struct RunLocationSection: Identifiable {
    let location: Location
    let packOrder: Int
    let machines: [RunMachineSection]

    var id: String { location.id }
    var machineCount: Int { machines.count }
    var coilCount: Int { machines.reduce(into: 0) { $0 += $1.coilCount } }
}

fileprivate struct NotPackedLocationSection: Identifiable {
    let location: Location
    let items: [RunCoil]

    var id: String { location.id }
}

fileprivate func formattedOrderDescription(for packOrder: Int) -> String {
    guard packOrder > 0 else { return "Unscheduled" }
    if packOrder == 1 {
        return "1 (deliver last)"
    }
    return "\(packOrder)"
}

struct RunDetailView: View {
    @Bindable var run: Run
    @EnvironmentObject private var sessionController: PackingSessionController
    @Environment(\.openURL) private var openURL
    @Environment(\.haptics) private var haptics
    @AppStorage(SettingsKeys.navigationApp) private var navigationAppRawValue: String = NavigationApp.appleMaps.rawValue
    @State private var isPresentingOrderEditor = false

    private var navigationApp: NavigationApp {
        NavigationApp(rawValue: navigationAppRawValue) ?? .appleMaps
    }

    private var locationSections: [RunLocationSection] {
        Self.locationSections(for: run)
    }

    private var notPackedSections: [NotPackedLocationSection] {
        Self.notPackedSections(for: run)
    }

    private var notPackedCount: Int {
        notPackedSections.reduce(into: 0) { $0 += $1.items.count }
    }

    fileprivate static func locationSections(for run: Run) -> [RunLocationSection] {
        var byLocation: [String: [RunCoil]] = [:]

        for runCoil in run.runCoils {
            guard let location = runCoil.coil.machine.location else { continue }
            byLocation[location.id, default: []].append(runCoil)
        }

        return byLocation.compactMap { _, runCoils in
            guard let location = runCoils.first?.coil.machine.location else { return nil }

            let machines = Dictionary(grouping: runCoils) { $0.coil.machine.id }
                .compactMap { _, machineCoils -> RunMachineSection? in
                    guard let machine = machineCoils.first?.coil.machine else { return nil }
                    let sortedCoils = machineCoils.sorted { lhs, rhs in
                        if lhs.packOrder == rhs.packOrder {
                            return lhs.coil.machinePointer.localizedStandardCompare(rhs.coil.machinePointer) == .orderedAscending
                        }
                        return lhs.packOrder < rhs.packOrder
                    }
                    return RunMachineSection(machine: machine, coils: sortedCoils)
                }
                .sorted {
                    $0.machine.name.localizedCaseInsensitiveCompare($1.machine.name) == .orderedAscending
                }

            let locationOrder = runCoils.map { Int($0.packOrder) }.min() ?? Int.max
            let safeOrder = locationOrder == Int.max ? 0 : locationOrder
            return RunLocationSection(location: location,
                                      packOrder: safeOrder,
                                      machines: machines)
        }
        .sorted {
            if $0.packOrder == $1.packOrder {
                return $0.location.name.localizedCaseInsensitiveCompare($1.location.name) == .orderedAscending
            }
            return $0.packOrder < $1.packOrder
        }
    }

    fileprivate static func notPackedSections(for run: Run) -> [NotPackedLocationSection] {
        let filtered = run.runCoils.filter { !$0.packed && $0.pick > 0 }
        var byLocation: [String: [RunCoil]] = [:]

        for runCoil in filtered {
            guard let location = runCoil.coil.machine.location else { continue }
            byLocation[location.id, default: []].append(runCoil)
        }

        return byLocation.compactMap { _, runCoils in
            guard let location = runCoils.first?.coil.machine.location else { return nil }

            let sortedItems = runCoils.sorted { lhs, rhs in
                let lhsMachine = lhs.coil.machine.name
                let rhsMachine = rhs.coil.machine.name
                if lhsMachine != rhsMachine {
                    return lhsMachine.localizedCaseInsensitiveCompare(rhsMachine) == .orderedAscending
                }
                return lhs.coil.machinePointer.localizedStandardCompare(rhs.coil.machinePointer) == .orderedAscending
            }

            return NotPackedLocationSection(location: location, items: sortedItems)
        }
        .sorted {
            $0.location.name.localizedCaseInsensitiveCompare($1.location.name) == .orderedAscending
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
                                 notPackedCount: max(totalCoils - packedCount, 0))
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
                    Label("Start Packing Session", systemImage: "tray.2")
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
                        Label("Start Packing Session", systemImage: "tray.2")
                    }
                    .disabled(run.runCoils.isEmpty)
                    
                    Button {
                        isPresentingOrderEditor = true
                    } label: {
                        Label("Reorder Locations", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(locationSections.count <= 1)

                    Button {
                        markAllRunItemsAsUnpacked()
                    } label: {
                        Label("Reset Packing Status for All Locations", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!hasPackedItems)
                    
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

private struct LocationsSectionHeader: View {
    let locationCount: Int

    private var subtitle: String {
        guard locationCount > 0 else { return "No locations" }
        let label = locationCount == 1 ? "location" : "locations"
        return "\(locationCount) \(label)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "house")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.18))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("LOCATIONS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

private struct RunLocationRow: View {
    let section: RunLocationSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.location.name)
                    .font(.headline)
                Spacer()
                Text("Order \(formattedOrderDescription(for: section.packOrder))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !section.location.address.isEmpty {
                Text(section.location.address)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("\(section.machineCount) \(section.machineCount == 1 ? "machine" : "machines") • \(section.coilCount) \(section.coilCount == 1 ? "coil" : "coils")")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

fileprivate struct RunLocationDetailView: View {
    @EnvironmentObject private var sessionController: PackingSessionController
    @Environment(\.haptics) private var haptics
    let run: Run
    let section: RunLocationSection

    private var locationRunCoils: [RunCoil] {
        section.machines.flatMap(\.coils)
    }

    private var packedCount: Int {
        locationRunCoils.filter(\.packed).count
    }

    private var notPackedCount: Int {
        max(locationRunCoils.count - packedCount, 0)
    }

    private var hasPackedItems: Bool {
        locationRunCoils.contains(where: \.packed)
    }

    var body: some View {
        List {
            Section {
                LocationOverviewBento(section: section,
                                      packedCount: packedCount,
                                      notPackedCount: notPackedCount)
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                Text("Location Overview")
            }

            ForEach(section.machines) { machineSection in
                Section(machineSection.machine.name) {
                    ForEach(machineSection.coils) { runCoil in
                        CoilRow(runCoil: runCoil)
                    }
                }
            }
        }
        .navigationTitle(section.location.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        sessionController.beginSession(for: run)
                    } label: {
                        Label("Start Packing", systemImage: "tray.2")
                    }
                    .disabled(locationRunCoils.isEmpty)
                    .accessibilityLabel("Start packing session")
                    Button {
                        haptics.secondaryButtonTap()
                        markAllItemsAsUnpacked()
                    } label: {
                        Label("Reset Packing Status", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!hasPackedItems)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Run actions")
            }
        }
    }

    private func markAllItemsAsUnpacked() {
        guard hasPackedItems else { return }
        withAnimation {
            for runCoil in locationRunCoils {
                runCoil.packed = false
            }
        }
    }
}

private struct RunOverviewBento: View {
    let run: Run
    let locationSections: [RunLocationSection]
    let machineCount: Int
    let totalCoils: Int
    let packedCount: Int
    let notPackedCount: Int

    private var items: [BentoItem] {
        var cards: [BentoItem] = []

        cards.append(
            BentoItem(title: "Run Date",
                      value: run.date.formatted(.dateTime.day().month().year()),
                      subtitle: run.date.formatted(.dateTime.weekday(.wide)),
                      symbolName: "calendar",
                      symbolTint: .indigo)
        )

        if !run.runner.isEmpty {
            cards.append(
                BentoItem(title: "Runner",
                          value: run.runner,
                          subtitle: "Assigned",
                          symbolName: "person.crop.circle",
                          symbolTint: .blue,
                          allowsMultilineValue: true)
            )
        }

        cards.append(
            BentoItem(title: "Machines",
                      value: "\(machineCount)",
                      subtitle: machineCount == 1 ? "machine" : "machines",
                      symbolName: "building.2",
                      symbolTint: .cyan)
        )

        cards.append(
            BentoItem(title: "Total Coils",
                      value: "\(totalCoils)",
                      subtitle: totalCoils == 1 ? "coil" : "coils",
                      symbolName: "scope",
                      symbolTint: .purple)
        )

        if totalCoils > 0 {
            let completion = Double(packedCount) / Double(totalCoils)
            let percent = Int((completion * 100).rounded())
            cards.append(
                BentoItem(title: "Packed",
                          value: "\(packedCount)",
                          subtitle: "\(percent)% complete",
                          symbolName: "checkmark.circle",
                          symbolTint: .green,
                          isProminent: true)
            )
        } else {
            cards.append(
                BentoItem(title: "Packed",
                          value: "0",
                          subtitle: "Awaiting items",
                          symbolName: "checkmark.circle",
                          symbolTint: .green)
            )
        }

        if notPackedCount > 0 {
            cards.append(
                BentoItem(title: "Remaining",
                          value: "\(notPackedCount)",
                          subtitle: "View items",
                          symbolName: "cart",
                          symbolTint: .pink,
                          isProminent: true,
                          destination: { AnyView(NotPackedItemsView(run: run)) },
                          showsChevron: true)
            )
        }

        return cards
    }

    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
    }
}

private struct LocationOverviewBento: View {
    let section: RunLocationSection
    let packedCount: Int
    let notPackedCount: Int

    private var metricItems: [BentoItem] {
        var cards: [BentoItem] = []

        cards.append(
            BentoItem(title: "Order",
                      value: formattedOrderDescription(for: section.packOrder),
                      subtitle: "Delivery sequence",
                      symbolName: "list.number",
                      symbolTint: .blue)
        )

        cards.append(
            BentoItem(title: "Machines",
                      value: "\(section.machineCount)",
                      subtitle: section.machineCount == 1 ? "machine" : "machines",
                      symbolName: "gearshape.2.fill",
                      symbolTint: .teal)
        )

        cards.append(
            BentoItem(title: "Total Coils",
                      value: "\(section.coilCount)",
                      subtitle: section.coilCount == 1 ? "coil" : "coils",
                      symbolName: "bolt.fill",
                      symbolTint: .purple)
        )

        if section.coilCount > 0 {
            let completion = Double(packedCount) / Double(section.coilCount)
            let percent = Int((completion * 100).rounded())
            cards.append(
                BentoItem(title: "Packed",
                          value: "\(packedCount)",
                          subtitle: "\(percent)% complete",
                          symbolName: "checkmark.circle.fill",
                          symbolTint: .green,
                          isProminent: true)
            )
        } else {
            cards.append(
                BentoItem(title: "Packed",
                          value: "0",
                          subtitle: "Awaiting items",
                          symbolName: "checkmark.circle",
                          symbolTint: .green)
            )
        }

        if notPackedCount > 0 {
            cards.append(
                BentoItem(title: "Remaining",
                          value: "\(notPackedCount)",
                          subtitle: "Still to pack",
                          symbolName: "shippingbox.fill",
                          symbolTint: .orange,
                          isProminent: true)
            )
        }

        return cards
    }

    private var addressItem: BentoItem? {
        guard !section.location.address.isEmpty else { return nil }
        return BentoItem(title: "Address",
                         value: section.location.address,
                         subtitle: nil,
                         symbolName: "mappin.circle.fill",
                         symbolTint: .pink,
                         allowsMultilineValue: true)
    }

    var body: some View {
        VStack(spacing: 10) {
            StaggeredBentoGrid(items: metricItems, columnCount: 2)
                .padding(.horizontal, 4)
            if let addressItem {
                BentoCard(item: addressItem)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct BentoItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let subtitle: String?
    let symbolName: String
    let symbolTint: Color
    let isProminent: Bool
    let allowsMultilineValue: Bool
    let destination: (() -> AnyView)?
    let showsChevron: Bool

    init(title: String,
         value: String,
         subtitle: String? = nil,
         symbolName: String,
         symbolTint: Color,
         isProminent: Bool = false,
         allowsMultilineValue: Bool = false,
         destination: (() -> AnyView)? = nil,
         showsChevron: Bool = false) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.symbolTint = symbolTint
        self.isProminent = isProminent
        self.allowsMultilineValue = allowsMultilineValue
        self.destination = destination
        self.showsChevron = showsChevron
    }
}

private struct StaggeredBentoGrid: View {
    let items: [BentoItem]
    let columnCount: Int

    @State private var isPresentingDestination = false
    @State private var activeDestination: AnyView?

    private var columns: [[BentoItem]] {
        let count = max(columnCount, 1)
        guard count > 1 else { return [items] }

        var buckets = Array(repeating: [BentoItem](), count: count)
        var index = 0
        for item in items {
            buckets[index].append(item)
            index = (index + 1) % count
        }
        return buckets
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, columnItems in
                VStack(spacing: 10) {
                    ForEach(columnItems) { item in
                        if let destination = item.destination {
                            Button {
                                activeDestination = destination()
                                isPresentingDestination = true
                            } label: {
                                BentoCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        } else {
                            BentoCard(item: item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationDestination(isPresented: $isPresentingDestination) {
            Group {
                if let destination = activeDestination {
                    destination
                } else {
                    EmptyView()
                }
            }
        }
        .onChange(of: isPresentingDestination) { oldValue, newValue in
            if oldValue && !newValue {
                activeDestination = nil
            }
        }
    }
}

private struct BentoCard: View {
    let item: BentoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(item.symbolTint)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(item.symbolTint.opacity(0.18))
                    )
                Text(item.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.value)
                    .font(item.isProminent ? .title2.weight(.semibold) : .title3.weight(.semibold))
                    .foregroundStyle(item.isProminent ? item.symbolTint : .primary)
                    .lineLimit(item.allowsMultilineValue ? nil : 2)
                    .multilineTextAlignment(.leading)
            }
            
            HStack {
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(item.allowsMultilineValue ? nil : 2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if item.showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.35))
        )
        .accessibilityElement(children: .combine)
    }
}

private struct NotPackedItemsView: View {
    @Bindable var run: Run

    private var sections: [NotPackedLocationSection] {
        RunDetailView.notPackedSections(for: run)
    }

    var body: some View {
        List {
            if sections.isEmpty {
                Text("All items were packed.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sections) { section in
                    Section(section.location.name) {
                        ForEach(section.items) { runCoil in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(runCoil.coil.item.name)
                                        .font(.headline)
                                    Text(runCoil.coil.machine.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Need \(max(runCoil.pick, 0))")
                                    .font(.headline)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Not Packed")
        .navigationBarTitleDisplayMode(.inline)
    }
}

fileprivate struct CoilRow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionController: PackingSessionController
    @Environment(\.haptics) private var haptics
    @Bindable var runCoil: RunCoil
    @State private var isDeleteConfirmationPresented = false
    @State private var isSessionRestartAlertPresented = false
    @State private var pendingPackedValue: Bool = false

    private var coil: Coil { runCoil.coil }
    private var item: Item { coil.item }
    private var machine: Machine { coil.machine }

    private var itemDescriptor: String {
        if item.type.isEmpty {
            return item.name
        }
        return "\(item.name) - \(item.type)"
    }

    private var isAnnouncing: Bool {
        guard let session = sessionController.activeSession,
              session.run.id == runCoil.run.id else {
            return false
        }
        let viewModel = session.viewModel
        guard viewModel.isSessionRunning else { return false }
        return viewModel.currentRunCoilID == runCoil.id
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            toggleButton
            VStack(alignment: .leading, spacing: 4) {
                Text(item.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(itemDescriptor)
                    .font(.headline)
                Text("Machine \(machine.id) - Coil \(coil.machinePointer)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            labelValue(title: "Need", value: runCoil.pick)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                isDeleteConfirmationPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .confirmationDialog("Remove Item?",
                            isPresented: $isDeleteConfirmationPresented,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteRunCoil()
            }
            Button("Cancel") { }
        } message: {
            Text("Are you sure you want to remove \(itemDescriptor) from this run?")
        }
        .alert("Packing Session Active",
               isPresented: $isSessionRestartAlertPresented) {
            Button("No", role: .cancel) {
                pendingPackedValue = false
            }
            Button("Continue") {
                handleSessionRestartContinue()
            }
        } message: {
            Text("To manually check this item off, your packing session has to be stopped and restarted, continue?")
        }
    }

    private var toggleButton: some View {
        Button {
            handleToggleTap()
        } label: {
            ZStack {
                Image(systemName: runCoil.packed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(runCoil.packed ? Color.green : Color(.tertiaryLabel))
                    .opacity(isAnnouncing ? 0 : 1)
                if isAnnouncing {
                    Image(systemName: "speaker.wave.2.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.title3.weight(.semibold))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(runCoil.packed ? "Mark as unpacked" : "Mark as packed")
    }

    @ViewBuilder
    private func labelValue(title: String, value: Int64) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.subheadline)
                .bold()
        }
    }

    private var isSessionRunningForRun: Bool {
        guard let session = sessionController.activeSession,
              session.run.id == runCoil.run.id else {
            return false
        }
        return session.viewModel.isSessionRunning
    }

    private func handleToggleTap() {
        let newValue = !runCoil.packed
        if newValue && isSessionRunningForRun {
            haptics.warning()
            pendingPackedValue = newValue
            isSessionRestartAlertPresented = true
        } else {
            applyToggle(newValue)
        }
    }

    private func applyToggle(_ newValue: Bool) {
        if newValue {
            haptics.success()
        } else {
            haptics.selectionChanged()
        }
        withAnimation {
            runCoil.packed = newValue
        }
    }

    private func deleteRunCoil() {
        haptics.destructiveActionTap()
        let run = runCoil.run
        let identifier = runCoil.id
        if isAnnouncing {
            sessionController.activeSession?.viewModel.stepForward()
        }
        withAnimation {
            if let index = run.runCoils.firstIndex(where: { $0.id == identifier }) {
                run.runCoils.remove(at: index)
            }
            modelContext.delete(runCoil)
        }
        isDeleteConfirmationPresented = false
    }

    private func handleSessionRestartContinue() {
        haptics.warning()
        guard isSessionRunningForRun else {
            applyToggle(pendingPackedValue)
            isSessionRestartAlertPresented = false
            pendingPackedValue = false
            return
        }
        let run = runCoil.run
        applyToggle(pendingPackedValue)
        sessionController.endSession()
        sessionController.beginSession(for: run)
        isSessionRestartAlertPresented = false
        pendingPackedValue = false
    }
}

fileprivate struct LocationOrderEditor: View {
    struct Item: Identifiable, Equatable {
        let id: String
        let name: String
        var packOrder: Int
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.haptics) private var haptics
    @State private var items: [Item]
    private let onSave: ([Item]) -> Void

    init(items: [Item], onSave: @escaping ([Item]) -> Void) {
        let sorted = items.sorted { lhs, rhs in
            if lhs.packOrder == rhs.packOrder {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.packOrder < rhs.packOrder
        }
        _items = State(initialValue: sorted)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        Text(item.name)
                    }
                }
                .onMove { indices, newOffset in
                    items.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .navigationTitle("Reorder Locations")
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        haptics.secondaryButtonTap()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        haptics.prominentActionTap()
                        saveAndDismiss()
                    }
                }
            }
        }
    }

    private func saveAndDismiss() {
        var updated = items
        for index in updated.indices {
            updated[index].packOrder = index + 1
        }
        onSave(updated)
        dismiss()
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
        if let locationSection = RunDetailView.locationSections(for: PreviewFixtures.sampleRun).first {
            RunLocationDetailView(run: PreviewFixtures.sampleRun, section: locationSection)
        } else {
            Text("Missing preview data")
        }
    }
    .environmentObject(PackingSessionController())
    .modelContainer(PreviewFixtures.container)
}
