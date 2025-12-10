//
//  ChartLoadingView.swift
//  PickAgent
//
//  Created by ChatGPT on 3/6/2026.
//

import SwiftUI

struct ChartLoadingView: View {
    var height: CGFloat = 220

    var body: some View {
        ZStack {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.gray)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

struct ChartLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .opacity(0.65)
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

extension View {
    func chartLoadingOverlay(isPresented: Bool) -> some View {
        overlay {
            if isPresented {
                ChartLoadingOverlay()
            }
        }
    }
}
