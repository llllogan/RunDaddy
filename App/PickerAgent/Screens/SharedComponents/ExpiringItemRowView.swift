import SwiftUI

struct ExpiringItemRowView: View {
    let skuName: String
    let skuType: String?
    let machineCode: String
    let coilCode: String
    let quantity: Int
    let stockingMessage: String?
    let stockingMessageColor: Color

    init(
        skuName: String,
        skuType: String? = nil,
        machineCode: String,
        coilCode: String,
        quantity: Int,
        stockingMessage: String? = nil,
        stockingMessageColor: Color = .secondary
    ) {
        self.skuName = skuName
        self.skuType = skuType
        self.machineCode = machineCode
        self.coilCode = coilCode
        self.quantity = quantity
        self.stockingMessage = stockingMessage
        self.stockingMessageColor = stockingMessageColor
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(skuName)
                    .font(.headline)
                    .lineLimit(2)

                if let skuType, !skuType.isEmpty {
                    Text(skuType)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("\(machineCode) • Coil \(coilCode)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let stockingMessage, !stockingMessage.isEmpty {
                    Text(stockingMessage)
                        .font(.footnote)
                        .foregroundStyle(stockingMessageColor)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(quantity)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("EXPIRING")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
