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

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(foregroundColour ?? .secondary)
            }
            
            if let title = title {
                Text(title.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(foregroundColour ?? .secondary)
            }
            
            if let text = text {
                Text(text)
                    .foregroundStyle(foregroundColour ?? .secondary)
                    .font(.caption2.bold())
                
            } else if let date = date {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(foregroundColour ?? .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(colour != nil ? Color(colour!) : Color(.systemGray5))
        .clipShape(Capsule())
    }
}
