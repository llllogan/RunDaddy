//
//  InfoChip.swift
//  PickerAgent
//
//  Created by Logan Janssen | Codify on 12/11/2025.
//

import SwiftUI
import Foundation

struct InfoChip: View {
    let title: String?
    let date: Date?
    let text: String?
    let colour: Color?
    let foregroundColour: Color?
    let icon: String?
    let iconColour: Color?
    
    init(
        title: String? = nil,
        date: Date? = nil,
        text: String? = nil,
        colour: Color? = nil,
        foregroundColour: Color? = nil,
        icon: String? = nil,
        iconColour: Color? = nil
    ) {
        self.title = title
        self.date = date
        self.text = text
        self.colour = colour
        self.foregroundColour = foregroundColour
        self.icon = icon
        self.iconColour = iconColour
    }

    var body: some View {
        let resolvedIconColour = iconColour ?? foregroundColour ?? .secondary
        let resolvedTextColour: Color = iconColour == nil ? resolvedIconColour : (foregroundColour ?? .secondary)

        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(resolvedIconColour)
            }
            
            if let title = title {
                Text(title.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(resolvedTextColour)
            }
            
            if let text = text {
                Text(text)
                    .foregroundStyle(resolvedTextColour)
                    .font(.caption2.bold())
                
            } else if let date = date {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(resolvedTextColour)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(colour ?? Color(.systemGray5))
        .clipShape(Capsule())
    }
}

struct EntityResultRow: View {
    private let iconSystemName: String
    private let iconColor: Color
    private let headline: String
    private let subheadline: String?
    private let isSelected: Bool
    private let verticalPadding: CGFloat
    private let showsSubheadline: Bool
    private let iconDiameter: CGFloat
    private let iconFontSize: CGFloat

    init(
        result: SearchResult,
        isSelected: Bool = false,
        verticalPadding: CGFloat = 4,
        showsSubheadline: Bool = true,
        iconDiameter: CGFloat = 36,
        iconFontSize: CGFloat = 16
    ) {
        let style = EntityResultRow.style(for: result.type)
        let content = EntityResultRow.content(forType: result.type, title: result.title, subtitle: result.subtitle)
        self.iconSystemName = style.systemName
        self.iconColor = style.color
        self.headline = content.headline
        self.subheadline = content.subheadline
        self.isSelected = isSelected
        self.verticalPadding = verticalPadding
        self.showsSubheadline = showsSubheadline
        self.iconDiameter = iconDiameter
        self.iconFontSize = iconFontSize
    }

    init(
        option: NoteTagOption,
        isSelected: Bool = false,
        verticalPadding: CGFloat = 4,
        showsSubheadline: Bool = true,
        iconDiameter: CGFloat = 36,
        iconFontSize: CGFloat = 16
    ) {
        let style = EntityResultRow.style(for: option.type)
        let content = EntityResultRow.content(forType: option.type.rawValue, title: option.label, subtitle: option.subtitle ?? "")
        self.iconSystemName = style.systemName
        self.iconColor = style.color
        self.headline = content.headline
        self.subheadline = content.subheadline
        self.isSelected = isSelected
        self.verticalPadding = verticalPadding
        self.showsSubheadline = showsSubheadline
        self.iconDiameter = iconDiameter
        self.iconFontSize = iconFontSize
    }

    init(
        target: NoteTarget,
        verticalPadding: CGFloat = 4,
        showsSubheadline: Bool = true,
        iconDiameter: CGFloat = 36,
        iconFontSize: CGFloat = 16
    ) {
        let style = EntityResultRow.style(for: target.type)
        let content = EntityResultRow.content(forType: target.type.rawValue, title: target.label, subtitle: target.subtitle ?? "")
        self.iconSystemName = style.systemName
        self.iconColor = style.color
        self.headline = content.headline
        self.subheadline = content.subheadline
        self.isSelected = false
        self.verticalPadding = verticalPadding
        self.showsSubheadline = showsSubheadline
        self.iconDiameter = iconDiameter
        self.iconFontSize = iconFontSize
    }

    var body: some View {
        HStack(spacing: showsSubheadline ? 12 : 6) {
            Image(systemName: iconSystemName)
                .font(.system(size: iconFontSize, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: iconDiameter, height: iconDiameter)
                .background(iconColor.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.headline)
                if showsSubheadline, let subheadline, !subheadline.isEmpty {
                    Text(subheadline)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, verticalPadding)
    }

    private struct EntityStyle {
        let systemName: String
        let color: Color
    }

    private static func style(for type: String) -> EntityStyle {
        switch type.lowercased() {
        case "machine":
            return EntityStyle(systemName: "building", color: .purple)
        case "sku":
            return EntityStyle(systemName: "tag", color: .teal)
        case "location":
            return EntityStyle(systemName: "mappin.circle", color: .orange)
        default:
            return EntityStyle(systemName: "magnifyingglass", color: .gray)
        }
    }

    private static func style(for type: NoteTargetType) -> EntityStyle {
        style(for: type.rawValue)
    }

    private static func content(forType type: String, title: String, subtitle: String) -> (headline: String, subheadline: String?) {
        switch type.lowercased() {
        case "machine":
            let display = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return (display.isEmpty ? title : display, title)
        case "sku":
            let components = subtitle
                .split(separator: "•")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let skuName = components.first
            let skuDetails = components.dropFirst().joined(separator: " • ")

            let headline = skuName ?? (subtitle.isEmpty ? title : subtitle)

            var parts: [String] = []
            if !skuDetails.isEmpty {
                parts.append(skuDetails)
            }
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                parts.append(trimmedTitle)
            }

            return (headline, parts.isEmpty ? nil : parts.joined(separator: " • "))
        default:
            let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, trimmedSubtitle.isEmpty ? nil : trimmedSubtitle)
        }
    }
}
