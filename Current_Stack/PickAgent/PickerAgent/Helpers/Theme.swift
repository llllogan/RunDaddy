//
//  Theme.swift
//  PickAgent
//
//  Created by Logan Janssen on 3/12/2025.
//

import SwiftUI

enum Theme {
    /// Theme color that switches between black (light mode) and white (dark mode).
    static var blackOnWhite: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .white : .black
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
}
