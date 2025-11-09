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
    let onTap: (() -> Void)?
    let showsChevron: Bool
    let customContent: AnyView?

    init(title: String,
         value: String,
         subtitle: String? = nil,
         symbolName: String,
         symbolTint: Color,
         isProminent: Bool = false,
         allowsMultilineValue: Bool = false,
         onTap: (() -> Void)? = nil,
         showsChevron: Bool = false,
         customContent: AnyView? = nil) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.symbolTint = symbolTint
        self.isProminent = isProminent
        self.allowsMultilineValue = allowsMultilineValue
        self.onTap = onTap
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
                        if let onTap = item.onTap {
                            Button {
                                onTap()
                            } label: {
                                BentoCard(item: item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            BentoCard(item: item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}


extension String {
    var statusDisplay: String {
        self
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

struct RunOverviewBento: View {
    let summary: RunOverviewSummary
    let viewModel: RunDetailViewModel
    let assignAction: (String) -> Void
    let pendingItemsTap: () -> Void

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
        
        if let currentStatus = viewModel.detail?.status {
            cards.append(
                BentoItem(title: "Status",
                          value: "",
                          symbolName: "flag",
                          symbolTint: .orange,
                          allowsMultilineValue: false,
                          customContent: AnyView(
                            Menu {
                                Button("Created") {
                                    Task {
                                        await viewModel.updateRunStatus(to: "CREATED")
                                    }
                                }
                                Button("Picking") {
                                    Task {
                                        await viewModel.updateRunStatus(to: "PICKING")
                                    }
                                }
                                Button("Pending Fresh") {
                                    Task {
                                        await viewModel.updateRunStatus(to: "PENDING_FRESH")
                                    }
                                }
                                Button("Ready") {
                                    Task {
                                        await viewModel.updateRunStatus(to: "READY")
                                    }
                                }
                            } label: {
                                HStack(spacing: 2) {
                                    Text(currentStatus.statusDisplay)
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
        }
        
        cards.append(
            BentoItem(title: "Machines",
                      value: "\(summary.machineCount)",
                      symbolName: "building.2",
                      symbolTint: .cyan)
        )
        
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
                             RunnerAssignButtons(viewModel: viewModel)
                          )
                         )
            )
        }
        
        cards.append(
            BentoItem(title: "Remaining",
                      value: "\(summary.remainingCoils)",
                      subtitle: summary.remainingCoils == 0 ? "All coils picked" : "Coils waiting to pack",
                      symbolName: "cart",
                      symbolTint: .pink,
                      isProminent: true,
                      onTap: pendingItemsTap,
                      showsChevron: true)
        )

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
                             PickerAssignButtons(viewModel: viewModel)
                           )
                         )
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

struct RunnerAssignButtons: View {
    let viewModel: RunDetailViewModel
    
    var body: some View {
        HStack(spacing: 0) {
            Button("Assign me") {
                print("Runner Assign Me button tapped")
                Task { @MainActor in
                    await viewModel.assignUser(to: "RUNNER")
                }
            }
            .lineLimit(1)
            .font(.subheadline)
            .padding(.horizontal, 8)
            .frame(minHeight: 40)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
            .buttonStyle(.plain)
            
            Menu {
                ForEach(viewModel.companyUsers) { user in
                    Button(user.displayName) {
                        Task {
                            await viewModel.assignUser(userId: user.id, to: "RUNNER")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                .tint(.primary)
                .labelStyle(.iconOnly)
                .padding()
                .background(Color(.systemGray5))
                .clipShape(Circle())
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
    }
}

struct PickerAssignButtons: View {
    let viewModel: RunDetailViewModel
    
    var body: some View {
        HStack(spacing: 0) {
            Button("Assign me") {
                Task { @MainActor in
                    await viewModel.assignUser(to: "PICKER")
                }
            }
            .lineLimit(1)
            .font(.subheadline)
            .padding(.horizontal, 8)
            .frame(minHeight: 40)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
            .buttonStyle(.plain)
            
            Menu {
                ForEach(viewModel.companyUsers) { user in
                    Button(user.displayName) {
                        Task {
                            await viewModel.assignUser(userId: user.id, to: "PICKER")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                .tint(.primary)
                .labelStyle(.iconOnly)
                .padding()
                .background(Color(.systemGray5))
                .clipShape(Circle())
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
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
    let cheeseItems: [RunDetail.PickItem]

    init(summary: LocationOverviewSummary, machines: [RunDetail.Machine] = [], viewModel: RunDetailViewModel, onChocolateBoxesTap: (() -> Void)? = nil, cheeseItems: [RunDetail.PickItem] = []) {
        self.summary = summary
        self.machines = machines
        self.viewModel = viewModel
        self.onChocolateBoxesTap = onChocolateBoxesTap
        self.cheeseItems = cheeseItems
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
                      subtitle: summary.remainingCoils == 0 ? "All coils picked" : "Coils waiting to pack",
                      symbolName: "cart",
                      symbolTint: .pink,
                      isProminent: summary.remainingCoils > 0)
        )
        
        cards.append(
            BentoItem(title: "Cheese Items",
                      value: "",
                      subtitle: cheeseItems.count == 0 ? "No cheese products" : "",
                      symbolName: "list.bullet.clipboard",
                      symbolTint: .yellow,
                      isProminent: cheeseItems.count > 0,
                      customContent: AnyView(
                        VStack(alignment: .leading, spacing: 4) {
                            if cheeseItems.isEmpty {
                                Text("None")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            } else {
                                let groupedCheeseItems = Dictionary(grouping: cheeseItems) { item in
                                    item.sku?.type ?? "Unknown SKU"
                                }
                                
                                ForEach(Array(groupedCheeseItems.keys.sorted()), id: \.self) { skuType in
                                    let items = groupedCheeseItems[skuType] ?? []
                                    let totalCount = items.reduce(0) { $0 + $1.count }
                                    
                                    HStack {
                                        Text(skuType)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(totalCount)")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                      ))
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
