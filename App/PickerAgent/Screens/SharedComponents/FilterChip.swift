//
//  FilterChip.swift
//  PickerAgent
//
//  Created by Logan Janssen | Codify on 12/11/2025.
//

import SwiftUI

func filterChip(label: String) -> some View {
    HStack(spacing: 2) {
        Text(label)
            .font(.subheadline)
        Image(systemName: "chevron.up.chevron.down")
            .font(.caption)
    }
    .padding(4)
    .padding(.horizontal, 6)
    .background(Color(.systemGray5))
    .clipShape(RoundedRectangle(cornerRadius: 6))
}
