//
//  Theme.swift
//  PickAgent
//
//  Created by Logan Janssen on 3/12/2025.
//

import SwiftUI
import Foundation
import UIKit

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
    
    /// Accent color for cold chest items (fresh/frozen; formerly "fresh chest")
    static var coldChestTint: Color {
        Color(red: 0.20, green: 0.66, blue: 0.93)
    }
    
    static var packingSessionBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .systemGray4 : .systemGray5
        })
    }
}

extension View {
    func keyboardDismissToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.dismissKeyboard()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Dismiss Keyboard")
            }
        }
    }
}

extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
