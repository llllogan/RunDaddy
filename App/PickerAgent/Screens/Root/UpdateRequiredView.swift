//
//  UpdateRequiredView.swift
//  PickAgent
//
//  Created by ChatGPT on 3/5/2026.
//

import SwiftUI

struct UpdateRequiredView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    let requiredVersion: String
    private let currentVersion = AppVersion.current

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.tint)

                VStack(spacing: 8) {
                    Text("Update Required")
                        .font(.title.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text("This version (\(currentVersion)) is behind the required version (\(requiredVersion)). Please update the app from the App Store or TestFlight to continue.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        await authViewModel.bootstrap()
                    }
                } label: {
                    Text("I've Updated - Check Again")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.blackOnWhite))
                        .foregroundStyle(Theme.contrastOnBlackOnWhite)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
