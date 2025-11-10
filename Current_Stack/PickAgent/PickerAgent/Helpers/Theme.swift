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
}
