import SwiftUI

struct SearchLocationInfoBento: View {
    let location: Location
    let lastPacked: LocationLastPacked?
    let bestSku: LocationBestSku?
    let hoursDisplay: HoursDisplay?
    let onConfigureHours: (() -> Void)?
    let canConfigureHours: Bool
    let firstSeen: String?
    
    init(
        location: Location,
        lastPacked: LocationLastPacked?,
        bestSku: LocationBestSku?,
        hoursDisplay: HoursDisplay? = nil,
        onConfigureHours: (() -> Void)? = nil,
        canConfigureHours: Bool = true,
        firstSeen: String? = nil
    ) {
        self.location = location
        self.lastPacked = lastPacked
        self.bestSku = bestSku
        self.hoursDisplay = hoursDisplay
        self.onConfigureHours = onConfigureHours
        self.canConfigureHours = canConfigureHours
        self.firstSeen = firstSeen
    }

    private var items: [BentoItem] {
        var cards: [BentoItem] = []

        cards.append(addressCard)

        if let hoursDisplay, let onConfigureHours {
            cards.append(
                BentoItem(
                    id: "location-info-hours",
                    title: "Hours",
                    value: "",
                    symbolName: "clock",
                    symbolTint: .blue,
                    allowsMultilineValue: true,
                    customContent: AnyView(
                        VStack(alignment: .leading, spacing: 10) {
                            HoursSummaryView(display: hoursDisplay)
                            
                            if canConfigureHours {
                                Button(action: onConfigureHours) {
                                    Text("Configure")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .foregroundStyle(Color(.secondaryLabel))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    )
                )
            )
        }

        cards.append(firstSeenCard)

        cards.append(
            BentoItem(
                id: "location-info-last-packed",
                title: lastPackedTitle,
                value: lastPackedValue,
                symbolName: "clock.arrow.circlepath",
                symbolTint: .indigo,
                allowsMultilineValue: true
            )
        )

//        if let bestSku = bestSku {
//            cards.append(
//                BentoItem(
//                    title: "Best SKU",
//                    value: bestSku.displayName,
//                    subtitle: bestSku.totalPacks > 0 ? "\(bestSku.totalPacks) packs" : nil,
//                    symbolName: "tag",
//                    symbolTint: .teal,
//                    allowsMultilineValue: true,
//                    onTap: { onBestSkuTap?(bestSku) },
//                    showsChevron: true
//                )
//            )
//        } else {
//            cards.append(
//                BentoItem(
//                    title: "Best SKU",
//                    value: "No data",
//                    subtitle: "No SKU activity",
//                    symbolName: "tag",
//                    symbolTint: .gray
//                )
//            )
//        }
        

        return cards
    }

    private var addressCard: BentoItem {
        BentoItem(
            id: "location-info-address",
            title: "Address",
            value: addressValue,
            symbolName: "mappin.circle",
            symbolTint: .orange,
            allowsMultilineValue: true,
            customContent: AnyView(
                AddressDetailView(
                    components: addressComponents,
                    fallback: addressValue
                )
            )
        )
    }

    private var addressValue: String {
        let trimmed = location.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "No address available" : trimmed
    }

    private var firstSeenCard: BentoItem {
        guard let firstSeen,
              let firstSeenDate = parseDate(firstSeen) else {
            return BentoItem(
                id: "location-info-first-seen",
                title: "First Seen",
                value: "No data",
                symbolName: "calendar.badge.clock",
                symbolTint: .secondary
            )
        }

        return BentoItem(
            id: "location-info-first-seen",
            title: "First Seen",
            value: formatRelativeDay(from: firstSeenDate),
            subtitle: SearchLocationInfoBento.weekdayFormatter.string(from: firstSeenDate),
            symbolName: "calendar.badge.clock",
            symbolTint: .blue,
            allowsMultilineValue: true
        )
    }

    private var addressComponents: AddressComponents? {
        AddressComponents.parse(from: location.address)
    }

    private var lastPackedTitle: String {
        guard let lastPacked,
              let date = parseDate(lastPacked.pickedAt) else {
            return "Last Packed"
        }
        return date > Date() ? "Next Packed" : "Last Packed"
    }

    private var lastPackedValue: String {
        guard let lastPacked else { return "No pick history" }
        return formatDate(lastPacked.pickedAt)
    }

    private var lastPackedSubtitle: String? {
        lastPacked?.machineDisplayName
    }

    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
    }

    private func formatDate(_ isoString: String) -> String {
        guard let date = SearchLocationInfoBento.isoFormatter.date(from: isoString) ?? SearchLocationInfoBento.basicIsoFormatter.date(from: isoString) else {
            return isoString
        }
        return formatRelativeDay(from: date)
    }

    private func parseDate(_ isoString: String) -> Date? {
        if let date = SearchLocationInfoBento.isoFormatter.date(from: isoString) {
            return date
        }
        return SearchLocationInfoBento.basicIsoFormatter.date(from: isoString)
    }

    private func formatRelativeDay(from date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        return SearchLocationInfoBento.dayMonthFormatter.string(from: date)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basicIsoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale.current
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = Locale.current
        return formatter
    }()
}

struct HoursDisplay {
    let opening: String
    let closing: String
    let dwell: String
}

private struct AddressDetailView: View {
    let components: AddressComponents?
    let fallback: String

    @State private var isExpanded = false

    private var hasParsedDetails: Bool {
        guard let components else { return false }
        return !components.isEmpty
    }

    private var hasExpandableDetails: Bool {
        guard let components else { return false }
        return components.suburbLine != nil || components.state != nil || components.country != nil
    }

    private var headlineLine: String {
        components?.street ?? fallback
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headlineLine)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            if isExpanded {
                if let suburbLine = components?.suburbLine {
                    AddressDetailRow(label: "Suburb", value: suburbLine)
                }

                if let state = components?.state {
                    AddressDetailRow(label: "State", value: state)
                }

                if let country = components?.country {
                    AddressDetailRow(label: "Country", value: country)
                }

                if !hasParsedDetails {
                    Text(fallback)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }

            if hasExpandableDetails {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "Hide details" : "Show more")
                            .font(.caption)
                        Spacer(minLength: 4)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddressDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct AddressComponents {
    let street: String?
    let suburb: String?
    let state: String?
    let postalCode: String?
    let country: String?

    var suburbLine: String? {
        let parts = [suburb, postalCode].compactMap { $0?.trimmedNonEmpty }
        let joined = parts.joined(separator: " ")
        return joined.trimmedNonEmpty
    }

    var isEmpty: Bool {
        [street, suburb, state, postalCode, country].allSatisfy { ($0?.isEmpty ?? true) }
    }

    static func parse(from address: String?) -> AddressComponents? {
        guard let cleanedAddress = address?.trimmedNonEmpty else {
            return nil
        }

        let segments = cleanedAddress
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let street = segments.first?.trimmedNonEmpty
        var country: String?

        var localitySegments = Array(segments.dropFirst())
        if localitySegments.count > 1 {
            country = localitySegments.removeLast().trimmedNonEmpty
        }

        let locality = localitySegments.joined(separator: ", ")
        let (suburb, state, postalCode) = parseLocality(locality)

        let parsed = AddressComponents(
            street: street,
            suburb: suburb,
            state: state,
            postalCode: postalCode,
            country: country
        )

        return parsed.isEmpty ? nil : parsed
    }

    private static func parseLocality(_ text: String) -> (String?, String?, String?) {
        var tokens = text
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }

        var postalCode: String?
        if let last = tokens.last, last.isNumericOnly {
            postalCode = last
            tokens.removeLast()
        }

        var state: String?
        if let last = tokens.last,
           last.range(of: #"^[A-Za-z]{2,3}$"#, options: .regularExpression) != nil {
            state = last
            tokens.removeLast()
        }

        let suburb = tokens.joined(separator: " ").trimmedNonEmpty

        return (suburb, state, postalCode)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isNumericOnly: Bool {
        !isEmpty && allSatisfy(\.isNumber)
    }
}

struct SearchLocationPerformanceBento: View {
    let percentageChange: PickEntryBreakdown.PercentageChange?
    let machineSalesShare: [LocationMachineSalesShare]
    let machines: [LocationMachine]
    let selectedPeriod: SkuPeriod?
    let onMachineTap: ((LocationMachine) -> Void)?
    let highMark: PickEntryBreakdown.Extremum?
    let lowMark: PickEntryBreakdown.Extremum?
    let aggregation: PickEntryBreakdown.Aggregation
    let timeZoneIdentifier: String

    private var items: [BentoItem] {
        [
            packTrendCard,
            shareOfSalesCard,
            highMarkCard,
            lowMarkCard
        ]
    }

    private var packTrendCard: BentoItem {
        BentoItem(
            id: "location-perf-pack-trend",
            title: "Pack Trend",
            value: formatPercentageChange(percentageChange),
            subtitle: formatTrendSubtitle(percentageChange?.trend, period: selectedPeriod),
            symbolName: trendSymbol(percentageChange?.trend),
            symbolTint: trendColor(percentageChange?.trend),
            isProminent: true
        )
    }

    private var shareOfSalesCard: BentoItem {
        BentoItem(
            id: "location-perf-share-of-sales",
            title: "Share of Sales",
            value: "",
            symbolName: "building.2",
            symbolTint: .purple,
            customContent: AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    if machines.isEmpty {
                        Text("No machines")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(machinesBySalesShare) { machine in
                            machineRow(for: machine)
                                .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            )
        )
    }

    private var highMarkCard: BentoItem {
        extremumCard(
            title: "High",
            extremum: highMark,
            symbolName: "arrow.up.to.line",
            tint: .green,
            isProminent: false
        )
    }

    private var lowMarkCard: BentoItem {
        extremumCard(
            title: "Low",
            extremum: lowMark,
            symbolName: "arrow.down.to.line",
            tint: .orange,
            isProminent: false
        )
    }

    @ViewBuilder
    private func machineRow(for machine: LocationMachine) -> some View {
        let isBestMachine = bestMachineId == machine.id

        let row = VStack(alignment: .leading, spacing: 4) {
            if let description = machine.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Text(description)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if let machineType = machine.machineType {
                Text(machineType.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 8) {
                InfoChip(
                    title: machineShareText(for: machine),
                    colour: isBestMachine ? .green.opacity(0.15) : .blue.opacity(0.15),
                    foregroundColour: isBestMachine ? .green : .blue
                )
                if onMachineTap != nil {
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let onMachineTap {
            Button {
                onMachineTap(machine)
            } label: {
                row
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            row
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var machineShareLookup: [String: LocationMachineSalesShare] {
        Dictionary(uniqueKeysWithValues: machineSalesShare.map { ($0.machineId, $0) })
    }

    private func machineShareText(for machine: LocationMachine) -> String {
        machineShareLookup[machine.id]?.roundedPercentageText ?? "0% of sales"
    }

    private func machineShareValue(for machine: LocationMachine) -> Double {
        machineShareLookup[machine.id]?.percentage ?? 0
    }

    private var machinesBySalesShare: [LocationMachine] {
        machines.sorted { first, second in
            let firstShare = machineShareValue(for: first)
            let secondShare = machineShareValue(for: second)
            if firstShare == secondShare {
                return first.id < second.id
            }
            return firstShare > secondShare
        }
    }

    private var bestMachineId: String? {
        guard let machine = machinesBySalesShare.first,
              machineShareValue(for: machine) > 0 else {
            return nil
        }
        return machine.id
    }

    var body: some View {
        StaggeredBentoGrid(items: items, columnCount: 2)
    }

    private func formatPercentageChange(_ change: PickEntryBreakdown.PercentageChange?) -> String {
        guard let change = change else { return "No data" }
        return String(format: "%@%.1f%%", change.value >= 0 ? "+" : "", change.value)
    }

    private func formatTrendSubtitle(_ trend: String?, period: SkuPeriod?) -> String {
        switch trend {
        case "up":
            return "Up from previous \(period?.displayName ?? "period")"
        case "down":
            return "Down from previous \(period?.displayName ?? "period")"
        case "neutral":
            return "Stable vs previous \(period?.displayName ?? "period")"
        default:
            return "No data"
        }
    }

    private func trendSymbol(_ trend: String?) -> String {
        switch trend {
        case "up":
            return "arrow.up.forward"
        case "down":
            return "arrow.down.right"
        default:
            return "minus"
        }
    }

    private func trendColor(_ trend: String?) -> Color {
        switch trend {
        case "up":
            return .green
        case "down":
            return .red
        default:
            return .gray
        }
    }

    private func extremumCard(
        title: String,
        extremum: PickEntryBreakdown.Extremum?,
        symbolName: String,
        tint: Color,
        isProminent: Bool
    ) -> BentoItem {
        guard let extremum else {
            return BentoItem(
                id: "location-perf-\(title.lowercased())",
                title: title,
                value: "No data",
                symbolName: symbolName,
                symbolTint: .secondary
            )
        }

        return BentoItem(
            id: "location-perf-\(title.lowercased())",
            title: title,
            value: BreakdownExtremumFormatter.valueText(for: extremum),
            subtitle: BreakdownExtremumFormatter.subtitle(
                for: extremum,
                aggregation: aggregation,
                timeZoneIdentifier: timeZoneIdentifier
            ),
            symbolName: symbolName,
            symbolTint: tint,
            isProminent: isProminent
        )
    }
}

private struct HoursSummaryView: View {
    let display: HoursDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(label: "Opens at", value: display.opening)
            row(label: "Closes at", value: display.closing)
            row(label: "Dwell time", value: display.dwell)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}
