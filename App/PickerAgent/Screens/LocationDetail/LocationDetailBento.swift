//
//  LocationDetailBento.swift
//  PickerAgent
//
//  Created by Logan Janssen on 13/11/2025.
//

import SwiftUI

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
