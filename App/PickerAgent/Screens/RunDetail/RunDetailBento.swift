//
//  RunDetailBento.swift
//  PickerAgent
//
//  Created by Logan Janssen on 13/11/2025.
//

import SwiftUI

struct RunOverviewBento: View {
    let summary: RunOverviewSummary
    let viewModel: RunDetailViewModel
    let pendingItemsTap: () -> Void
    let notesTap: () -> Void
    let freshChestChips: [FreshChestSkuChip]

    private var packers: [RunDetail.Packer] {
        viewModel.detail?.packers ?? []
    }

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
                                    HapticsService.shared.statusChanged()
                                    Task {
                                        await viewModel.updateRunStatus(to: "CREATED")
                                    }
                                }
                                Button("Picking") {
                                    HapticsService.shared.statusChanged()
                                    Task {
                                        await viewModel.updateRunStatus(to: "PICKING")
                                    }
                                }
                                Button("Pending Fresh") {
                                    HapticsService.shared.statusChanged()
                                    Task {
                                        await viewModel.updateRunStatus(to: "PENDING_FRESH")
                                    }
                                }
                                Button("Ready") {
                                    HapticsService.shared.statusChanged()
                                    Task {
                                        await viewModel.updateRunStatus(to: "READY")
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(currentStatus.statusDisplay)
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.subheadline.weight(.medium))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            }
                            .tint(.primary)
                          )
                         )
            )
        }
        
//        cards.append(
//            BentoItem(title: "Machines",
//                      value: "\(summary.machineCount)",
//                      symbolName: "building.2",
//                      symbolTint: .purple)
//        )
        
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
                                        HapticsService.shared.userAssigned()
                                        Task {
                                            await viewModel.assignUser(userId: user.id, to: "RUNNER")
                                        }
                                    }
                                }
                                Divider()
                                Button("Unassign") {
                                    HapticsService.shared.userUnassigned()
                                    Task {
                                        await viewModel.unassignUser(from: "RUNNER")
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(runner)
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.subheadline.weight(.medium))
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
            BentoItem(
                title: "Pickers",
                value: "",
                subtitle: packers.isEmpty ? "None" : "",
                symbolName: "person.crop.rectangle.stack",
                symbolTint: .blue,
                customContent: AnyView(
                    VStack(alignment: .leading, spacing: 8) {
                        if !packers.isEmpty {
                            ForEach(packers, id: \.id) { packer in
                                PackerRow(packer: packer)
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                )
            )
        )
        
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
        
        cards.append(
            BentoItem(
                title: "Notes",
                value: noteCountDisplay,
                subtitle: "Run + persistent",
                symbolName: "note.text",
                symbolTint: .purple,
                isProminent: true,
                onTap: notesTap,
                showsChevron: true
            )
        )

        if !freshChestChips.isEmpty {
            cards.append(
                BentoItem(
                    title: "Fresh Chest",
                    value: "",
                    symbolName: "leaf.fill",
                    symbolTint: Theme.freshChestTint,
                    isProminent: true,
                    customContent: AnyView(
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(freshChestChips) { chip in
                                HStack(spacing: 5) {
                                    Image(systemName: "leaf.fill")
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
                    )
                )
            )
        }
        
        cards.append(totalWeightCard)
        
        return cards
    }
    
    private var noteCountDisplay: String {
        if let count = viewModel.noteCount {
            return "\(count)"
        }
        return viewModel.isLoading ? "…" : "—"
    }

    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
    }

    private var totalWeightCard: BentoItem {
        let totalWeightKg = summary.totalWeightGrams / 1000
        let formatted = RunOverviewBento.weightFormatter.string(from: NSNumber(value: totalWeightKg))
            ?? "\(totalWeightKg)"

        let subtitle: String? = summary.itemsMissingWeight > 0
            ? "\(summary.itemsMissingWeight) without weight"
            : nil

        return BentoItem(
            title: "Total Weight",
            value: "\(formatted) kg",
            subtitle: subtitle,
            symbolName: "scalemass",
            symbolTint: .orange,
            isProminent: false
        )
    }

    private static let weightFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

struct RunnerAssignButtons: View {
    let viewModel: RunDetailViewModel
    
    var body: some View {
        HStack(spacing: 0) {
            Button("Assign me") {
                HapticsService.shared.userAssigned()
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
                        HapticsService.shared.userAssigned()
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

private struct PackerRow: View {
    let packer: RunDetail.Packer

    private var emailText: String? {
        guard let email = packer.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else {
            return nil
        }
        return email
    }

    private var sessionCountText: String {
        let count = packer.sessionCount
        return count == 1 ? "1 session" : "\(count) sessions"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(packer.displayName)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 6) {
                InfoChip(
                    text: sessionCountText,
                    colour: Color.blue.opacity(0.14),
                    foregroundColour: .blue
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
