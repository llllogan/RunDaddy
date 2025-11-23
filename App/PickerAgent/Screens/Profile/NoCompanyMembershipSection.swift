//
//  NoCompanyMembershipSection.swift
//  PickAgent
//
//  Created by ChatGPT on 5/8/2025.
//

import SwiftUI

struct NoCompanyMembershipSection: View {
    var onJoinTapped: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("No Company Membership")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Text("You're currently logged in without a company. To access runs and other features, you'll need to join or create a company.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Join Company") {
                    onJoinTapped()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    NavigationStack {
        List {
            NoCompanyMembershipSection(onJoinTapped: {})
        }
    }
}
