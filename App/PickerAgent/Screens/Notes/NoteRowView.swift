import SwiftUI

struct NoteRowView: View {
    let note: Note
    let runDate: Date?

    init(note: Note, runDate: Date? = nil) {
        self.note = note
        self.runDate = runDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                if let authorLabel {
                    Text(authorLabel)
                        .font(.caption2.italic())
                        .foregroundStyle(.secondary)
                    
                    Text("at")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(note.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(note.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                InfoChip(
                    title: nil,
                    text: note.target.targetDisplayLabel,
                    colour: note.target.type.tint.opacity(0.14),
                    foregroundColour: note.target.type.tint,
                    icon: note.target.iconName,
                    iconColour: note.target.type.tint
                )

                if let runDateText {
                    InfoChip(
                        title: "For run",
                        text: runDateText,
                        colour: Color.orange.opacity(0.14),
                        foregroundColour: .orange,
                        icon: "calendar",
                    )
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var runDateText: String? {
        guard note.scope == .run, let runDate else {
            return nil
        }

        return runDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var authorLabel: String? {
        let trimmed = note.authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension NoteTarget {
    var targetDisplayLabel: String {
        switch type {
        case .machine:
            // Only surface the machine description (carried in subtitle)
            if let subtitle = subtitle, !subtitle.isEmpty {
                return subtitle
            }
            return label
        case .sku:
            if let subtitle = subtitle, !subtitle.isEmpty {
                return subtitle
            }
            return label
        case .location:
            return label
        }
    }

    var iconName: String {
        switch type {
        case .sku:
            return "tag"
        case .machine:
            return "building.fill"
        case .location:
            return "mappin.circle"
        }
    }
}

private extension NoteTargetType {
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
}
