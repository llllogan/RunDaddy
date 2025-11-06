//
//  SharedComponents.swift
//  PickAgent
//
//  Created by ChatGPT on 11/6/2025.
//

import SwiftUI

struct RunRow: View {
    let run: RunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(run.locationCount) \(run.locationCount > 1 ? "Locations" : "Location")")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 0) {
                Text("Runner: ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(run.runner?.displayName ?? "No runner yet")")
                    .font(.subheadline)
            }
            .padding(.bottom, 4)
            
            HStack(spacing: 6) {
                PillChip(title: nil, date: nil, text: run.statusDisplay, colour: statusBackgroundColor, foregroundColour: statusForegroundColor)
                
                if let started = run.pickingStartedAt {
                    PillChip(title: "Started", date: started, text: nil, colour: nil, foregroundColour: nil)
                }
                if let ended = run.pickingEndedAt {
                    PillChip(title: "Ended", date: ended, text: nil, colour: nil, foregroundColour: nil)
                }
            }
        }
        .padding(.vertical, 0)
    }

    private var statusBackgroundColor: Color {
        switch run.status {
        case "PENDING_FRESH":
            return .red.opacity(0.12)
        case "PICKING":
            return .orange.opacity(0.15)
        case "READY":
            return .green.opacity(0.15)
        default:
            return Color(.systemGray5)
        }
    }

    private var statusForegroundColor: Color {
        switch run.status {
        case "PENDING_FRESH":
            return .red
        case "PICKING":
            return .orange
        case "READY":
            return .green
        default:
            return .secondary
        }
    }
}

struct PillChip: View {
    let title: String?
    let date: Date?
    let text: String?
    let colour: Color?
    let foregroundColour: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let title = title {
                Text(title.uppercased())
                    .font(.caption2.bold())
            }
            
            if let text = text {
                Text(text)
                    .foregroundStyle(foregroundColour!)
                    .font(.caption2.bold())
                
            } else if let date = date {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(colour != nil ? Color(colour!) : Color(.systemGray6))
        .clipShape(Capsule())
    }
}

struct ErrorStateRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

struct EmptyStateRow: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

struct LoadingStateRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Theme.packageBrown)
            Text("Loading…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}
