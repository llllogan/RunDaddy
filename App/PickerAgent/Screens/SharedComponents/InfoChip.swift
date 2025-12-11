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
