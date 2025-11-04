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

    private var items: [BentoItem] {
        var cards: [BentoItem] = []

        cards.append(
            BentoItem(title: "Run Date",
                      value: summary.runDate.formatted(.dateTime.day().month().year()),
                      subtitle: summary.runDate.formatted(.dateTime.weekday(.wide)),
                      symbolName: "calendar",
                      symbolTint: .indigo)
        )

        if let runner = summary.runnerName, !runner.isEmpty {
            cards.append(
                BentoItem(title: "Runner",
                          value: runner,
                          symbolName: "person.crop.circle",
                          symbolTint: .blue,
                          allowsMultilineValue: true)
            )
        }

        cards.append(
            BentoItem(title: "Machines",
                      value: "\(summary.machineCount)",
                      symbolName: "building.2",
                      symbolTint: .cyan)
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

        cards.append(
            BentoItem(title: "Machines",
                      value: "\(summary.machineCount)",
                      symbolName: "building.2",
                      symbolTint: .cyan)
        )

        cards.append(
            BentoItem(title: "Total Coils",
                      value: "\(summary.totalCoils)",
                      symbolName: "scope",
                      symbolTint: .purple)
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

        if summary.totalItems > 0 {
            cards.append(
                BentoItem(title: "Total Items",
                          value: "\(summary.totalItems)",
                          symbolName: "cube",
                          symbolTint: .indigo,
                          isProminent: true)
            )
        }

        cards.append(
            BentoItem(title: "Remaining",
                      value: "\(summary.remainingCoils)",
                      subtitle: summary.remainingCoils == 0 ? "All coils picked" : "Waiting to pack",
                      symbolName: "cart",
                      symbolTint: .pink,
                      isProminent: summary.remainingCoils > 0)
        )

        return cards
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
