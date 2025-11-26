import SwiftUI

struct SearchLocationInfoBento: View {
    let location: Location
    let machines: [LocationMachine]
    let lastPacked: LocationLastPacked?
    let percentageChange: SkuPercentageChange?
    let bestSku: LocationBestSku?
    let machineSalesShare: [LocationMachineSalesShare]
    let selectedPeriod: SkuPeriod?
    let onBestSkuTap: ((LocationBestSku) -> Void)?
    let onMachineTap: ((LocationMachine) -> Void)?
    let hoursDisplay: HoursDisplay?
    let onConfigureHours: (() -> Void)?
    
    init(
        location: Location,
        machines: [LocationMachine],
        lastPacked: LocationLastPacked?,
        percentageChange: SkuPercentageChange?,
        bestSku: LocationBestSku?,
        machineSalesShare: [LocationMachineSalesShare],
        selectedPeriod: SkuPeriod?,
        onBestSkuTap: ((LocationBestSku) -> Void)? = nil,
        onMachineTap: ((LocationMachine) -> Void)? = nil,
        hoursDisplay: HoursDisplay? = nil,
        onConfigureHours: (() -> Void)? = nil
    ) {
        self.location = location
        self.machines = machines
        self.lastPacked = lastPacked
        self.percentageChange = percentageChange
        self.bestSku = bestSku
        self.machineSalesShare = machineSalesShare
        self.selectedPeriod = selectedPeriod
        self.onBestSkuTap = onBestSkuTap
        self.onMachineTap = onMachineTap
        self.hoursDisplay = hoursDisplay
        self.onConfigureHours = onConfigureHours
    }

    private var machineShareLookup: [String: LocationMachineSalesShare] {
        Dictionary(uniqueKeysWithValues: machineSalesShare.map { ($0.machineId, $0) })
    }

    private var items: [BentoItem] {
        var cards: [BentoItem] = []

        cards.append(
            BentoItem(
                title: "Address",
                value: addressValue,
                symbolName: "mappin.circle",
                symbolTint: .orange,
                allowsMultilineValue: true
            )
        )

        if let hoursDisplay, let onConfigureHours {
            cards.append(
                BentoItem(
                    title: "Hours",
                    value: "",
                    symbolName: "clock",
                    symbolTint: .blue,
                    allowsMultilineValue: true,
                    customContent: AnyView(
                        VStack(alignment: .leading, spacing: 10) {
                            HoursSummaryView(display: hoursDisplay)
                            Button(action: onConfigureHours) {
                                Text("Configure")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .foregroundStyle(Color(.secondaryLabel))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    )
                )
            )
        }

        cards.append(
            BentoItem(
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
        
        cards.append(
            BentoItem(
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
        )
        
        cards.append(
            BentoItem(
                title: "Pack Trend",
                value: formatPercentageChange(percentageChange),
                subtitle: formatTrendSubtitle(percentageChange?.trend, period: selectedPeriod),
                symbolName: trendSymbol(percentageChange?.trend),
                symbolTint: trendColor(percentageChange?.trend),
                isProminent: true
            )
        )

        

        return cards
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
                    date: nil,
                    text: nil,
                    colour: isBestMachine ? .green.opacity(0.15) : .blue.opacity(0.15),
                    foregroundColour: isBestMachine ? .green : .blue,
                    icon: nil
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

    private var addressValue: String {
        let trimmed = location.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "No address available" : trimmed
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

    private func formatPercentageChange(_ change: SkuPercentageChange?) -> String {
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
}

struct HoursDisplay {
    let opening: String
    let closing: String
    let dwell: String
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
