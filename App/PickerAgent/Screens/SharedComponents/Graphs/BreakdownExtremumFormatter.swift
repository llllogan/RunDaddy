import Foundation

enum BreakdownExtremumFormatter {
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func valueText(for extremum: PickEntryBreakdown.Extremum) -> String {
        let formatted = numberFormatter.string(from: NSNumber(value: extremum.totalItems)) ?? "\(extremum.totalItems)"
        return "\(formatted) items"
    }

    static func subtitle(
        for extremum: PickEntryBreakdown.Extremum,
        aggregation: PickEntryBreakdown.Aggregation,
        timeZoneIdentifier: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        switch aggregation {
        case .week:
            formatter.dateFormat = "EEE, MMM d"
        case .month:
            formatter.dateFormat = "'Week of' MMM d"
        case .quarter:
            formatter.dateFormat = "MMMM yyyy"
        }

        return formatter.string(from: extremum.start)
    }
}
