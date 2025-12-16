//
//  MaintenanceDownView.swift
//  PickAgent
//
//  Created by ChatGPT on 12/16/2025.
//

import SwiftUI

struct MaintenanceDownView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.tint)

                VStack(spacing: 8) {
                    Text("Maintenance")
                        .font(.title.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text("Picker Agent is down for maintenance. Please contact Logan if this looks wrong")
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
                    Text("Try Again")
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

