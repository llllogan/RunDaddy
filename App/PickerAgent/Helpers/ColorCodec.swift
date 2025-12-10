import SwiftUI
import UIKit

enum ColorCodec {
    /// Convert a stored hex string (with or without leading "#", with 6 or 8 characters) into a SwiftUI Color.
    static func color(fromHex hex: String?) -> Color? {
        guard var hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return nil
        }

        if hex.hasPrefix("#") {
            hex.removeFirst()
        }

        if hex.count == 6 {
            hex.append("FF") // Assume opaque if alpha missing.
        }

        guard hex.count == 8, let value = UInt64(hex, radix: 16) else {
            return nil
        }

        let red = Double((value & 0xFF00_0000) >> 24) / 255.0
        let green = Double((value & 0x00FF_0000) >> 16) / 255.0
        let blue = Double((value & 0x0000_FF00) >> 8) / 255.0
        let alpha = Double(value & 0x0000_00FF) / 255.0

        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Convert a SwiftUI Color into a hex string with alpha (#RRGGBBAA).
    static func hexString(from color: Color) -> String? {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        let r = Int(round(red * 255))
        let g = Int(round(green * 255))
        let b = Int(round(blue * 255))
        let a = Int(round(alpha * 255))

        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}
