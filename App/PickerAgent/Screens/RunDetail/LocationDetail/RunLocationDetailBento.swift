//
//  RunLocationDetailBento.swift
//  PickerAgent
//
//  Created by Logan Janssen on 13/11/2025.
//

import SwiftUI

struct RunLocationOverviewSummary {
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

struct RunLocationOverviewBento: View {
    let summary: RunLocationOverviewSummary
    let machines: [RunDetail.Machine]
    let viewModel: RunDetailViewModel
    let onChocolateBoxesTap: (() -> Void)?
    let onAddChocolateBoxTap: (() -> Void)?
    let coldChestItems: [RunDetail.PickItem]
    let showsColdChest: Bool
    let showsChocolateBoxes: Bool
    let onLocationTap: (() -> Void)?
    let onMachineTap: ((RunDetail.Machine) -> Void)?

    init(summary: RunLocationOverviewSummary,
         machines: [RunDetail.Machine] = [],
         viewModel: RunDetailViewModel,
         onChocolateBoxesTap: (() -> Void)? = nil,
         onAddChocolateBoxTap: (() -> Void)? = nil,
         coldChestItems: [RunDetail.PickItem] = [],
         showsColdChest: Bool = true,
         showsChocolateBoxes: Bool = true,
         onLocationTap: (() -> Void)? = nil,
         onMachineTap: ((RunDetail.Machine) -> Void)? = nil) {
        self.summary = summary
        self.machines = machines
        self.viewModel = viewModel
        self.onChocolateBoxesTap = onChocolateBoxesTap
        self.onAddChocolateBoxTap = onAddChocolateBoxTap
        self.coldChestItems = coldChestItems
        self.showsColdChest = showsColdChest
        self.showsChocolateBoxes = showsChocolateBoxes
        self.onLocationTap = onLocationTap
        self.onMachineTap = onMachineTap
    }

    private var items: [BentoItem] {
        var cards: [BentoItem] = []

        cards.append(
            BentoItem(title: "Location",
                      value: summary.title,
                      subtitle: summary.address,
                      symbolName: "mappin.circle",
                      symbolTint: .orange,
                      allowsMultilineValue: true,
                      onTap: onLocationTap,
                      showsChevron: onLocationTap != nil)
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
        
        if showsColdChest {
            cards.append(
                BentoItem(title: "Cold Chest",
                          value: "",
                          subtitle: coldChestItems.count == 0 ? "No cold chest items" : "",
                          symbolName: "snowflake",
                          symbolTint: Theme.coldChestTint,
                          isProminent: coldChestItems.count > 0,
                          customContent: AnyView(
                            VStack(alignment: .leading, spacing: 4) {
                                if !coldChestItems.isEmpty {
                                    ForEach(coldSkuChips) { chip in
                                        HStack(spacing: 5) {
                                            Image(systemName: "circle.fill")
                                                .font(.caption2.weight(.bold))
                                                .foregroundColor(chip.colour)
                                            Text(chip.label)
                                                .font(.footnote)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text("\(chip.count)")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                          ))
            )
        }

        cards.append(
            BentoItem(title: "Machines",
                      value: "",
                      symbolName: "building.2",
                      symbolTint: .purple,
                      customContent: AnyView(
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(machines, id: \.id) { machine in
                                machineRow(for: machine)
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

//        cards.append(
//            BentoItem(title: "Remaining",
//                      value: "\(summary.remainingCoils)",
//                      subtitle: summary.remainingCoils == 0 ? "All coils picked" : "Coils waiting to pack",
//                      symbolName: "cart",
//                      symbolTint: .pink,
//                      isProminent: summary.remainingCoils > 0)
//        )
        
        if showsChocolateBoxes {
            cards.append(
                BentoItem(title: "Chocolate Boxes",
                          value: "",
                          symbolName: "shippingbox",
                          symbolTint: .brown,
                          showsChevron: false,
                          customContent: AnyView(
                            VStack(alignment: .leading, spacing: 12) {
                                if locationChocolateBoxes.isEmpty {
                                    Text("No chocolate boxes")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(locationChocolateBoxes) { box in
                                            chocolateBoxRow(for: box)
                                        }
                                    }
                                }
                                
                                HStack {
                                    chocolateBoxesButton
                                    Spacer()
                                    addChocolateBoxButton
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                          ))
            )
        }

        return cards
    }

    private var coldSkuChips: [ColdChip] {
        let grouped = Dictionary(grouping: coldChestItems) { item -> String? in
            guard let sku = item.sku, sku.isFreshOrFrozen else { return nil }
            return sku.id
        }

        let chips = grouped.compactMap { key, items -> ColdChip? in
            guard let key, let sku = items.first?.sku else { return nil }
            let count = items.reduce(0) { $0 + max($1.count, 0) }
            let colour = ColorCodec.color(fromHex: sku.labelColour) ?? Theme.coldChestTint
            let label = sku.type
            return ColdChip(id: key, label: label, count: count, colour: colour)
        }

        return chips.sorted { lhs, rhs in
            lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    @ViewBuilder
    private func machineRow(for machine: RunDetail.Machine) -> some View {
        let details = VStack(alignment: .leading, spacing: 4) {
            if let description = machine.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Text(description)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            
            Text(machine.code)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let machineType = machine.machineType {
                HStack(alignment: .center, spacing: 8) {
                    InfoChip(text: machineType.description,
                             colour: Color.indigo.opacity(0.15),
                             foregroundColour: Color.indigo)
                    if onMachineTap != nil {
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if let onMachineTap {
            Button {
                onMachineTap(machine)
            } label: {
                details
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            details
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var locationChocolateBoxes: [RunDetail.ChocolateBox] {
        let locationMachineIds = Set(machines.map { $0.id })
        return viewModel.chocolateBoxes
            .filter { box in
                guard let machineId = box.machine?.id else { return false }
                return locationMachineIds.contains(machineId)
            }
            .sorted { lhs, rhs in
                let lhsName = machineName(for: lhs.machine)
                let rhsName = machineName(for: rhs.machine)
                
                if lhsName == rhsName {
                    return lhs.number < rhs.number
                }
                
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
    }
    
    @ViewBuilder
    private func chocolateBoxRow(for box: RunDetail.ChocolateBox) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(machineName(for: box.machine))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if let code = box.machine?.code {
                    Text(code)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 12)
            
            Text("\(box.number)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
    
    private func machineName(for machine: RunDetail.Machine?) -> String {
        if let description = machine?.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            return description
        }
        return machine?.code ?? "Unassigned"
    }
    
    private var chocolateBoxesButton: some View {
        Button {
            onChocolateBoxesTap?()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .padding(8)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .disabled(onChocolateBoxesTap == nil)
    }
    
    private var addChocolateBoxButton: some View {
        Button {
            onAddChocolateBoxTap?()
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .padding(8)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .disabled(onAddChocolateBoxTap == nil)
    }

    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
            .padding(.vertical, 2)
    }
}

private struct ColdChip: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int
    let colour: Color
}
