import SwiftUI

struct FilterToolbarButton: View {
    let label: String
    let systemImage: String
    let isActive: Bool

    var body: some View {
        let padding: CGFloat = isActive ? 8 : 6

        return Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .padding(padding)
            .background {
                if isActive {
                    Capsule().fill(Color.blue)
                } else {
                    Circle().fill(Color.clear)
                }
            }
            .accessibilityLabel(Text(label))
    }
}
