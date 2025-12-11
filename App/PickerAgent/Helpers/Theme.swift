//
//  Theme.swift
//  PickAgent
//
//  Created by Logan Janssen on 3/12/2025.
//

import SwiftUI
import Foundation

enum Theme {
    /// Theme color that switches between black (light mode) and white (dark mode).
    static var blackOnWhite: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .white : .black
        })
    }
    
    /// Complementary color to `blackOnWhite` for legible foregrounds on that background.
    static var contrastOnBlackOnWhite: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .black : .white
        })
    }
    
    /// Green color for positive trends
    static var trendUp: Color {
        .green.opacity(0.90)
    }
    
    /// Red color for negative trends
    static var trendDown: Color {
        .red.opacity(0.90)
    }
    
    /// Accent color for fresh/frozen items (formerly cheese tub)
    static var freshChestTint: Color {
        Color(red: 0.08, green: 0.45, blue: 0.28)
    }
    
    static var packingSessionBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .systemGray4 : .systemGray5
        })
    }
}
