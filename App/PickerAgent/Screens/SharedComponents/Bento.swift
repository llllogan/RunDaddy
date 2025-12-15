//
//  Bento.swift
//  PickAgent
//
//  Created by Logan Janssen on 4/11/2025.
//

import SwiftUI

struct BentoCard: View {
    let item: BentoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if item.showsSymbol {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(item.symbolTint)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(item.symbolTint.opacity(0.18))
                        )
                }
                titleText
            }

            if let customContent = item.customContent {
                customContent
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    valueText

                    Spacer(minLength: 8)

                    if let callout = item.callout, !callout.isEmpty {
                        calloutText(callout)
                    }
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

    @ViewBuilder
    private var titleText: some View {
        if item.titleIsProminent {
            Text(item.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
        } else {
            Text(item.title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var valueText: some View {
        let text = Text(item.value)
            .font(item.isProminent ? .title2.weight(.semibold) : .title3.weight(.semibold))
            .foregroundStyle(item.isProminent ? item.symbolTint : .primary)
            .lineLimit(item.allowsMultilineValue ? nil : 2)
            .multilineTextAlignment(.leading)

        if isMostlyNumeric(item.value) {
            text
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.35), value: item.value)
        } else {
            text
        }
    }

    @ViewBuilder
    private func calloutText(_ callout: String) -> some View {
        let text = Text(callout)
            .font(item.isProminent ? .title3.weight(.semibold) : .headline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(item.allowsMultilineValue ? nil : 2)
            .multilineTextAlignment(.trailing)

        if isMostlyNumeric(callout) {
            text
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.35), value: callout)
        } else {
            text
        }
    }

    private func isMostlyNumeric(_ text: String) -> Bool {
        text.contains(where: \.isNumber)
    }
}


struct BentoItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let callout: String?
    let subtitle: String?
    let symbolName: String
    let symbolTint: Color
    let showsSymbol: Bool
    let titleIsProminent: Bool
    let isProminent: Bool
    let allowsMultilineValue: Bool
    let onTap: (() -> Void)?
    let showsChevron: Bool
    let customContent: AnyView?

    init(id: String = UUID().uuidString,
         title: String,
         value: String,
         callout: String? = nil,
         subtitle: String? = nil,
         symbolName: String,
         symbolTint: Color,
         showsSymbol: Bool = true,
         titleIsProminent: Bool = false,
         isProminent: Bool = false,
         allowsMultilineValue: Bool = false,
         onTap: (() -> Void)? = nil,
         showsChevron: Bool = false,
         customContent: AnyView? = nil) {
        self.id = id
        self.title = title
        self.value = value
        self.callout = callout
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.symbolTint = symbolTint
        self.showsSymbol = showsSymbol
        self.titleIsProminent = titleIsProminent
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
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var effectiveColumnCount: Int {
        let baseCount = max(columnCount, 1)
        guard !items.isEmpty else {
            return baseCount
        }

        let shouldIncreaseColumns = horizontalSizeClass == .regular || verticalSizeClass == .compact
        let desiredCount = shouldIncreaseColumns ? (baseCount + 1) : baseCount
        return min(desiredCount, items.count)
    }

    private var columns: [[BentoItem]] {
        let safeCount = max(effectiveColumnCount, 1)
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
                            if item.customContent != nil {
                                BentoCard(item: item)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onTap() }
                            } else {
                                Button {
                                    onTap()
                                } label: {
                                    BentoCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
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
        if self == "PENDING_FRESH" {
            return "Pending Cold"
        }
        return self
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}


struct PackedGaugeChart: View {
    let progress: Double
    let totalCount: Int
    let tint: Color

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

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let progressWidth = max(proxy.size.width * clampedProgress, 0)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.systemGray6))

                    if progressWidth > 0 {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.gradient)
                            .frame(width: progressWidth)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(.separator).opacity(0.35))
                )
            }
            .frame(height: 14)

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
}
