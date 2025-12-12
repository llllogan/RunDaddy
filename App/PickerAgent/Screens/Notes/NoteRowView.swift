import SwiftUI

struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                InfoChip(
                    title: note.target.type.displayTitle,
                    text: note.target.label,
                    colour: note.target.type.tint.opacity(0.14),
                    foregroundColour: note.target.type.tint,
                    icon: note.target.type.iconName,
                    iconColour: note.target.type.tint
                )

                if note.scope == .persistent {
                    InfoChip(
                        text: "Persistent",
                        colour: Color.orange.opacity(0.14),
                        foregroundColour: .orange,
                        icon: "infinity"
                    )
                }

                Spacer(minLength: 0)

                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let subtitle = note.target.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }
}

private extension NoteTargetType {
    var iconName: String {
        switch self {
        case .sku:
            return "shippingbox"
        case .machine:
            return "gearshape"
        case .location:
            return "mappin.and.ellipse"
        }
    }

    var tint: Color {
        switch self {
        case .sku:
            return .blue
        case .machine:
            return .indigo
        case .location:
            return .green
        }
    }

    var displayTitle: String {
        switch self {
        case .sku:
            return "SKU"
        case .machine:
            return "Machine"
        case .location:
            return "Location"
        }
    }
}
