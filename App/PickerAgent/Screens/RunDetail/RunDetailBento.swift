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
                symbolName: "person.crop.rectangle.stack",
                symbolTint: .blue,
                customContent: AnyView(
                    VStack(alignment: .leading, spacing: 8) {
                        if packers.isEmpty {
                            Text("None so far.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
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
                    title: nil,
                    date: nil,
                    text: sessionCountText,
                    colour: Color.blue.opacity(0.14),
                    foregroundColour: .blue,
                    icon: nil
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
