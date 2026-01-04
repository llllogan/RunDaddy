import SwiftUI

struct FilterToolbarButton: View {
    let label: String
    let systemImage: String
    let isActive: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .padding(6)
            .background(isActive ? Color.blue : Color.clear, in: Circle())
            .accessibilityLabel(Text(label))
    }
}
