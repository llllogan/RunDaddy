//
//  RunDetailRows.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI

struct LocationsSectionHeader: View {
    let locationCount: Int

    private var subtitle: String {
        guard locationCount > 0 else { return "No locations" }
        let label = locationCount == 1 ? "location" : "locations"
        return "\(locationCount) \(label)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "house")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.18))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("LOCATIONS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

struct LocationMachinesSectionHeader: View {
    let machineCount: Int
    let coilCount: Int

    private var subtitle: String {
        guard machineCount > 0 else { return "No machines" }
        let machineLabel = machineCount == 1 ? "machine" : "machines"
        if coilCount == 0 {
            return "\(machineCount) \(machineLabel) • No coils"
        }
        let coilLabel = coilCount == 1 ? "coil" : "coils"
        return "\(machineCount) \(machineLabel) • \(coilCount) \(coilLabel)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.cyan)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.18))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("MACHINES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

struct RunLocationRow: View {
    let section: RunLocationSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.location.name)
                    .font(.headline)
                Spacer()
                Text("Order \(RunDetailFormatter.orderDescription(for: section.packOrder))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !section.location.address.isEmpty {
                Text(section.location.address)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("\(section.machineCount) \(section.machineCount == 1 ? "machine" : "machines") • \(section.coilCount) \(section.coilCount == 1 ? "coil" : "coils")")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
