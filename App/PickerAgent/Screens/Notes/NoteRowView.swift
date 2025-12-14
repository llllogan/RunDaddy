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

            EntityResultRow(
                target: note.target,
                verticalPadding: 0,
                showsSubheadline: false,
                iconDiameter: 22,
                iconFontSize: 12
            )

            Text(note.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                if let runDateText {
                    InfoChip(
                        title: "For run",
                        text: runDateText,
                        icon: "calendar"
                    )
                }
            }
        }
        .padding(.vertical, 2)
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
