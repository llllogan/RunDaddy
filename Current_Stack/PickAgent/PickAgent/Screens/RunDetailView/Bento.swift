//
//  Bento.swift
//  PickAgent
//
//  Created by Logan Janssen on 4/11/2025.
//

import SwiftUI
import Charts

struct BentoCard: View {
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

            if let customContent = item.customContent {
                customContent
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.value)
                        .font(item.isProminent ? .title2.weight(.semibold) : .title3.weight(.semibold))
                        .foregroundStyle(item.isProminent ? item.symbolTint : .primary)
                        .lineLimit(item.allowsMultilineValue ? nil : 2)
                        .multilineTextAlignment(.leading)
                }
            }

            if (item.subtitle?.isEmpty == false) || item.showsChevron {
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


struct BentoItem: Identifiable {
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
    let customContent: AnyView?

    init(title: String,
         value: String,
         subtitle: String? = nil,
         symbolName: String,
         symbolTint: Color,
         isProminent: Bool = false,
         allowsMultilineValue: Bool = false,
         destination: (() -> AnyView)? = nil,
         showsChevron: Bool = false,
         customContent: AnyView? = nil) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.symbolTint = symbolTint
        self.isProminent = isProminent
        self.allowsMultilineValue = allowsMultilineValue
        self.destination = destination
        self.showsChevron = showsChevron
        self.customContent = customContent
    }
}


struct StaggeredBentoGrid: View {
    let items: [BentoItem]
    let columnCount: Int

    private var columns: [[BentoItem]] {
        let safeCount = max(columnCount, 1)
        guard safeCount > 1 else {
            return [items]
        }

        var buckets: [[BentoItem]] = Array(repeating: [], count: safeCount)
        for (index, item) in items.enumerated() {
            buckets[index % safeCount].append(item)
        }
        return buckets
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(columns.indices, id: \.self) { index in
                VStack(spacing: 12) {
                    ForEach(columns[index]) { item in
                        BentoCard(item: item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}


struct RunOverviewBento: View {
    let summary: RunOverviewSummary
    let viewModel: RunDetailViewModel
    let assignAction: (String) -> Void

    private var items: [BentoItem] {
        var cards: [BentoItem] = []

        cards.append(
            BentoItem(title: "Run Date",
                      value: summary.runDate.formatted(.dateTime.day().month().year()),
                      subtitle: summary.runDate.formatted(.dateTime.weekday(.wide)),
                      symbolName: "calendar",
                      symbolTint: .indigo)
        )
        
        if summary.totalCoils > 0 {
            let completion = Double(summary.packedCoils) / Double(summary.totalCoils)
            cards.append(
                BentoItem(title: "Packed",
                          value: "\(summary.packedCoils) of \(summary.totalCoils)",
                          symbolName: "checkmark.circle",
                          symbolTint: .green,
                          customContent: AnyView(PackedGaugeChart(progress: completion,
                                                                   totalCount: summary.totalItems,
                                                                   tint: .green)))
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

        if let runner = summary.runnerName, !runner.isEmpty {
            cards.append(
                BentoItem(title: "Runner",
                          value: "",
                          symbolName: "person.crop.circle",
                          symbolTint: .blue,
                          allowsMultilineValue: false,
                          customContent: AnyView(
                            Menu {
                                ForEach(viewModel.companyUsers) { user in
                                    Button(user.displayName) {
                                        Task {
                                            await viewModel.assignUser(userId: user.id, to: "RUNNER")
                                        }
                                    }
                                }
                                Divider()
                                Button("Unassign") {
                                    Task {
                                        await viewModel.unassignUser(from: "RUNNER")
                                    }
                                }
                            } label: {
                                HStack(spacing: 2) {
                                    Text(runner)
                                        .font(.title3.weight(.semibold))
                                        .lineLimit(1)
                                    Image(systemName: "chevron.down")
                                        .font(.headline.weight(.medium))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            }
                            .tint(.primary)
                          )
                         )
            )
        } else {
            cards.append(
                BentoItem(title: "Runner",
                          value: "",
                          symbolName: "person.crop.circle.badge.questionmark",
                          symbolTint: .blue,
                          allowsMultilineValue: false,
                          customContent: AnyView(
                            HStack {
                                Button(action: {
                                    Task {
                                        await viewModel.assignUser(to: "RUNNER")
                                    }
                                }) {
                                    Text("Assign me")
                                        .font(.subheadline)
                                        .padding(.horizontal, 4)
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                            }
                         )
                         )
            )
        }

        if let picker = summary.pickerName, !picker.isEmpty {
            cards.append(
                BentoItem(title: "Picker",
                          value: "",
                          symbolName: "person.crop.circle",
                          symbolTint: .blue,
                          allowsMultilineValue: false,
                          customContent: AnyView(
                            Menu {
                                ForEach(viewModel.companyUsers) { user in
                                    Button(user.displayName) {
                                        Task {
                                            await viewModel.assignUser(userId: user.id, to: "PICKER")
                                        }
                                    }
                                }
                                Divider()
                                Button("Unassign") {
                                    Task {
                                        await viewModel.unassignUser(from: "PICKER")
                                    }
                                }
                            } label: {
                                HStack(spacing: 2) {
                                    Text(picker)
                                        .font(.title3.weight(.semibold))
                                        .lineLimit(1)
                                    Image(systemName: "chevron.down")
                                        .font(.headline.weight(.medium))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            }
                            .tint(.primary)
                          )
                         )
            )
        } else {
            cards.append(
                BentoItem(title: "Picker",
                          value: "",
                          symbolName: "person.crop.circle.badge.questionmark",
                          symbolTint: .blue,
                          allowsMultilineValue: false,
                          customContent: AnyView(
                            HStack {
                                Button(action: {
                                    Task {
                                        await viewModel.assignUser(to: "PICKER")
                                    }
                                }) {
                                    Text("Assign me")
                                        .font(.subheadline)
                                        .padding(.horizontal, 4)
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                            }
                          )
                         )
            )
        }

        cards.append(
            BentoItem(title: "Machines",
                      value: "\(summary.machineCount)",
                      symbolName: "building.2",
                      symbolTint: .cyan)
        )

        cards.append(
            BentoItem(title: "Remaining",
                      value: "\(summary.remainingCoils)",
                      subtitle: summary.remainingCoils == 0 ? "All coils picked" : "Waiting to pack",
                      symbolName: "cart",
                      symbolTint: .pink,
                      isProminent: true)
        )

        return cards
    }

    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
    }
}

struct LocationOverviewSummary {
    let title: String
    let address: String?
    let machineCount: Int
    let totalCoils: Int
    let packedCoils: Int
    let totalItems: Int

    var remainingCoils: Int {
        max(totalCoils - packedCoils, 0)
    }
}

struct LocationOverviewBento: View {
    let summary: LocationOverviewSummary
    let machines: [RunDetail.Machine]
    let viewModel: RunDetailViewModel
    let onChocolateBoxesTap: (() -> Void)?

    init(summary: LocationOverviewSummary, machines: [RunDetail.Machine] = [], viewModel: RunDetailViewModel, onChocolateBoxesTap: (() -> Void)? = nil) {
        self.summary = summary
        self.machines = machines
        self.viewModel = viewModel
        self.onChocolateBoxesTap = onChocolateBoxesTap
    }

    private var items: [BentoItem] {
        var cards: [BentoItem] = []

        cards.append(
            BentoItem(title: "Location",
                      value: summary.title,
                      subtitle: summary.address,
                      symbolName: "mappin.circle",
                      symbolTint: .orange,
                      allowsMultilineValue: true)
        )
        
        if summary.totalCoils > 0 {
            let completion = Double(summary.packedCoils) / Double(summary.totalCoils)
            cards.append(
                BentoItem(title: "Packed",
                          value: "\(summary.packedCoils) of \(summary.totalCoils)",
                          symbolName: "checkmark.circle",
                          symbolTint: .green,
                          customContent: AnyView(PackedGaugeChart(progress: completion,
                                                                   totalCount: summary.totalItems,
                                                                   tint: .green)))
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

        cards.append(
            BentoItem(title: "Machines",
                      value: "",
                      symbolName: "building.2",
                      symbolTint: .cyan,
                      customContent: AnyView(
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(machines, id: \.id) { machine in
                                VStack(alignment: .leading, spacing: 2) {
                                    
                                    if let description = machine.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(description)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                    
                                    HStack {
                                        Text(machine.code)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    
                                    if let machineType = machine.machineType {
                                        Text(machineType.name)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(.systemGray5))
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            
                            if machines.isEmpty {
                                Text("No machines")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                      ))
        )

//        cards.append(
//            BentoItem(title: "Total Coils",
//                      value: "\(summary.totalCoils)",
//                      symbolName: "scope",
//                      symbolTint: .purple)
//        )

        

//        if summary.totalItems > 0 {
//            cards.append(
//                BentoItem(title: "Total Items",
//                          value: "\(summary.totalItems)",
//                          symbolName: "cube",
//                          symbolTint: .indigo,
//                          isProminent: true)
//            )
//        }

        cards.append(
            BentoItem(title: "Remaining",
                      value: "\(summary.remainingCoils)",
                      subtitle: summary.remainingCoils == 0 ? "All coils picked" : "Waiting to pack",
                      symbolName: "cart",
                      symbolTint: .pink,
                      isProminent: summary.remainingCoils > 0)
        )
        
        cards.append(
            BentoItem(title: "Chocolate Boxes",
                      value: "",
                      symbolName: "shippingbox",
                      symbolTint: .brown,
                     customContent: AnyView(
                        HStack{
                            Text(chocolateBoxNumbersText)
                                .font(.title3.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Button(action: {
                                onChocolateBoxesTap?()
                            }) {
                                Image(systemName: "magnifyingglass")
                                    .padding(6)
                                    .background(Color(.systemGray5))
                                    .clipShape(Circle())
                                    .tint(.primary)
                            }
                        }
                     ))
        )

        return cards
    }

    private var chocolateBoxNumbersText: String {
        // Filter chocolate boxes to only include those assigned to machines in this location
        let locationMachineIds = Set(machines.map { $0.id })
        let locationChocolateBoxes = viewModel.chocolateBoxes.filter { box in
            box.machine?.id != nil && locationMachineIds.contains(box.machine!.id)
        }
        
        let numbers = locationChocolateBoxes.map { $0.number }.sorted()
        if numbers.isEmpty {
            return "None"
        } else if numbers.count <= 3 {
            return numbers.map(String.init).joined(separator: ", ")
        } else {
            return "\(numbers[0]), \(numbers[1]), \(numbers[2])..."
        }
    }

    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
    }
}

struct PackedGaugeChart: View {
    let progress: Double
    let totalCount: Int
    let tint: Color

    private enum GaugeSliceKind {
        case gap
        case progress
        case remainder
    }

    private struct GaugeSlice: Identifiable {
        let id = UUID()
        let kind: GaugeSliceKind
        let value: Double
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var packedPercentageText: String {
        let percentage = (clampedProgress * 100).rounded()
        return "\(Int(percentage))%"
    }

    private var totalCountText: String {
        guard totalCount != 1 else { return "1 item" }
        return "\(totalCount) items"
    }

    /// Creates donut slices that render a semi-circular gauge using a Swift Chart.
    private var slices: [GaugeSlice] {
        let gapPortion = 0.5
        let activePortion = 1 - gapPortion
        let filledPortion = clampedProgress * activePortion
        let remainingPortion = max(activePortion - filledPortion, 0)

        var items: [GaugeSlice] = [
            GaugeSlice(kind: .gap, value: gapPortion / 2)
        ]

        if filledPortion > 0 {
            items.append(GaugeSlice(kind: .progress, value: filledPortion))
        }

        if remainingPortion > 0 {
            items.append(GaugeSlice(kind: .remainder, value: remainingPortion))
        }

        items.append(GaugeSlice(kind: .gap, value: gapPortion / 2))

        return items
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let diameter = proxy.size.width

                Chart(slices) { slice in
                    SectorMark(angle: .value("Completion", slice.value),
                               innerRadius: .ratio(0.62),
                               outerRadius: .ratio(1.0))
                        .cornerRadius(6)
                        .foregroundStyle(style(for: slice.kind))
                        .opacity(slice.kind == .gap ? 0 : 1)
                }
                .chartLegend(.hidden)
                .rotationEffect(.degrees(180))
                .frame(width: diameter, height: diameter)
                .clipShape(SemiCircleClipShape())
                .frame(width: diameter, height: diameter / 2, alignment: .top)
            }
            .aspectRatio(2, contentMode: .fit)
            .layoutPriority(1)

            HStack {
                Text(packedPercentageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(totalCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Packed completion")
        .accessibilityValue(Text("\(Int((clampedProgress * 100).rounded())) percent"))
    }

    private func style(for kind: GaugeSliceKind) -> AnyShapeStyle {
        switch kind {
        case .gap:
            return AnyShapeStyle(Color.clear)
        case .progress:
            return AnyShapeStyle(tint.gradient)
        case .remainder:
            return AnyShapeStyle(Color(.systemGray5))
        }
    }
}

struct SemiCircleClipShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clipRect = CGRect(x: 0, y: 0, width: rect.width, height: rect.height / 2)
        path.addRect(clipRect)
        return path
    }
}




#Preview {
    struct PreviewRunsService: RunsServicing {
        func fetchRuns(for schedule: RunsSchedule, credentials: AuthCredentials) async throws -> [RunSummary] {
            []
        }

        func fetchRunDetail(withId runId: String, credentials: AuthCredentials) async throws -> RunDetail {
            let downtown = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
            let uptown = RunDetail.Location(id: "loc-2", name: "Uptown Annex", address: "456 Oak Avenue")

            let snackType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
            let drinkType = RunDetail.MachineTypeDescriptor(id: "type-2", name: "Drink Machine", description: nil)

            let machineA = RunDetail.Machine(id: "machine-1", code: "A-101", description: "Lobby", machineType: snackType, location: downtown)
            let machineB = RunDetail.Machine(id: "machine-2", code: "B-204", description: "Breakroom", machineType: snackType, location: downtown)
            let machineC = RunDetail.Machine(id: "machine-3", code: "C-08", description: "Front Vestibule", machineType: drinkType, location: uptown)

            let coilA = RunDetail.Coil(id: "coil-1", code: "C1", machineId: machineA.id)
            let coilB = RunDetail.Coil(id: "coil-2", code: "C2", machineId: machineB.id)
            let coilC = RunDetail.Coil(id: "coil-3", code: "C3", machineId: machineC.id)

            let coilItemA = RunDetail.CoilItem(id: "coil-item-1", par: 10, coil: coilA)
            let coilItemB = RunDetail.CoilItem(id: "coil-item-2", par: 8, coil: coilB)
            let coilItemC = RunDetail.CoilItem(id: "coil-item-3", par: 12, coil: coilC)

            let skuSnack = RunDetail.Sku(id: "sku-1", code: "SKU-001", name: "Trail Mix", type: "Snack", isCheeseAndCrackers: false)
            let skuDrink = RunDetail.Sku(id: "sku-2", code: "SKU-002", name: "Sparkling Water", type: "Beverage", isCheeseAndCrackers: false)

            let pickA = RunDetail.PickItem(id: "pick-1", count: 6, status: "PICKED", pickedAt: Date(), coilItem: coilItemA, sku: skuSnack, machine: machineA, location: downtown)
            let pickB = RunDetail.PickItem(id: "pick-2", count: 4, status: "PENDING", pickedAt: nil, coilItem: coilItemB, sku: skuSnack, machine: machineB, location: downtown)
            let pickC = RunDetail.PickItem(id: "pick-3", count: 9, status: "PICKED", pickedAt: Date().addingTimeInterval(-1200), coilItem: coilItemC, sku: skuDrink, machine: machineC, location: uptown)

            let chocolateBox = RunDetail.ChocolateBox(id: "box-1", number: 1, machine: machineA)

            return RunDetail(
                id: runId,
                status: "PICKING",
                companyId: "company-1",
                scheduledFor: Date().addingTimeInterval(3600),
                pickingStartedAt: Date().addingTimeInterval(-1800),
                pickingEndedAt: nil,
                createdAt: Date().addingTimeInterval(-7200),
                picker: RunParticipant(id: "picker-1", firstName: "Jordan", lastName: "Smith"),
                runner: nil,
                locations: [downtown, uptown],
                machines: [machineA, machineB, machineC],
                pickItems: [pickA, pickB, pickC],
                chocolateBoxes: [chocolateBox]
            )
        }

        func assignUser(to runId: String, userId: String, role: String, credentials: AuthCredentials) async throws {
            // Preview does nothing
        }
        
        func fetchCompanyUsers(credentials: AuthCredentials) async throws -> [CompanyUser] {
            return [
                CompanyUser(id: "user-1", email: "jordan@example.com", firstName: "Jordan", lastName: "Smith", phone: nil, role: "PICKER"),
                CompanyUser(id: "user-2", email: "alex@example.com", firstName: "Alex", lastName: "Johnson", phone: nil, role: "RUNNER"),
                CompanyUser(id: "user-3", email: "sam@example.com", firstName: "Sam", lastName: "Brown", phone: nil, role: "PICKER")
            ]
        }
        
        func updatePickItemStatus(runId: String, pickId: String, status: String, credentials: AuthCredentials) async throws {
            // Preview does nothing
        }
        
        func fetchChocolateBoxes(for runId: String, credentials: AuthCredentials) async throws -> [RunDetail.ChocolateBox] {
            let downtown = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
            let snackType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
            let machineA = RunDetail.Machine(id: "machine-1", code: "A-101", description: "Lobby", machineType: snackType, location: downtown)
            
            let chocolateBox1 = RunDetail.ChocolateBox(id: "box-1", number: 1, machine: machineA)
            let chocolateBox2 = RunDetail.ChocolateBox(id: "box-2", number: 34, machine: machineA)
            let chocolateBox3 = RunDetail.ChocolateBox(id: "box-3", number: 5, machine: nil)
            
            return [chocolateBox1, chocolateBox2, chocolateBox3]
        }
        
        func createChocolateBox(for runId: String, number: Int, machineId: String, credentials: AuthCredentials) async throws -> RunDetail.ChocolateBox {
            let downtown = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
            let snackType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
            let machineA = RunDetail.Machine(id: machineId, code: "A-101", description: "Lobby", machineType: snackType, location: downtown)
            
            return RunDetail.ChocolateBox(id: "new-box", number: number, machine: machineA)
        }
        
        func updateChocolateBox(for runId: String, boxId: String, number: Int?, machineId: String?, credentials: AuthCredentials) async throws -> RunDetail.ChocolateBox {
            let downtown = RunDetail.Location(id: "loc-1", name: "Downtown HQ", address: "123 Main Street")
            let snackType = RunDetail.MachineTypeDescriptor(id: "type-1", name: "Snack Machine", description: "Classic snacks")
            let machineA = RunDetail.Machine(id: machineId ?? "machine-1", code: "A-101", description: "Lobby", machineType: snackType, location: downtown)
            
            return RunDetail.ChocolateBox(id: boxId, number: number ?? 1, machine: machineA)
        }
        
        func deleteChocolateBox(for runId: String, boxId: String, credentials: AuthCredentials) async throws {
            // Preview does nothing
        }
    }

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

    return NavigationStack {
        RunDetailView(runId: "run-12345", session: session, service: PreviewRunsService())
            .environment(\.colorScheme, .light)
    }
}
