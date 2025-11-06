//
//  SharedComponents.swift
//  PickAgent
//
//  Created by ChatGPT on 11/6/2025.
//

import SwiftUI

struct FlowLayout: Layout {
    let spacing: CGFloat
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var totalHeight: CGFloat = 0
        
        for row in rows {
            let maxHeight = row.map { subview in
                subview.sizeThatFits(.unspecified).height
            }.max() ?? 0
            totalHeight += maxHeight
        }
        
        totalHeight += spacing * CGFloat(max(0, rows.count - 1))
        
        return CGSize(
            width: proposal.width ?? 0,
            height: totalHeight
        )
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        
        for row in rows {
            var x = bounds.minX
            let maxHeight = row.map { subview in
                subview.sizeThatFits(.unspecified).height
            }.max() ?? 0
            
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            
            y += maxHeight + spacing
        }
    }
    
    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = []
        var currentRow: [LayoutSubview] = []
        var currentWidth: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentWidth + size.width > maxWidth && !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = [subview]
                currentWidth = size.width
            } else {
                currentRow.append(subview)
                currentWidth += size.width + spacing
            }
        }
        
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
}

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
            
            FlowLayout(spacing: 6) {
                PillChip(title: nil, date: nil, text: run.statusDisplay, colour: statusBackgroundColor, foregroundColour: statusForegroundColor, icon: nil)
                
                if !run.chocolateBoxes.isEmpty {
                    PillChip(
                        title: nil,
                        date: nil,
                        text: run.chocolateBoxesDisplay,
                        colour: Theme.packageBrown.opacity(0.15),
                        foregroundColour: Theme.packageBrown,
                        icon: "shippingbox"
                    )
                }
                
                if let started = run.pickingStartedAt {
                    PillChip(title: "Started", date: started, text: nil, colour: nil, foregroundColour: nil, icon: nil)
                }
                if let ended = run.pickingEndedAt {
                    PillChip(title: "Ended", date: ended, text: nil, colour: nil, foregroundColour: nil, icon: nil)
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
    let icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(foregroundColour ?? .secondary)
            }
            
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
