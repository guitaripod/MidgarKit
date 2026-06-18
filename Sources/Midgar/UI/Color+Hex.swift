import UIKit

extension UIColor {
    /// Creates a color from a `#RRGGBB` or `#RRGGBBAA` hex string. Returns `nil` for malformed input.
    convenience init?(hex: String?) {
        guard let components = midgarRGBA(hex: hex) else { return nil }
        self.init(red: components.r, green: components.g, blue: components.b, alpha: components.a)
    }
}

/// Parses a hex color string into sRGB components in `0...1`. Free function so it can be unit-tested
/// without comparing opaque `UIColor` values.
func midgarRGBA(hex: String?) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
    guard var string = hex?.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased(),
          string.count == 6 || string.count == 8,
          string.allSatisfy({ $0.isHexDigit })
    else { return nil }

    if string.count == 6 { string += "FF" }
    guard let value = UInt32(string, radix: 16) else { return nil }
    return (
        r: CGFloat((value >> 24) & 0xFF) / 255,
        g: CGFloat((value >> 16) & 0xFF) / 255,
        b: CGFloat((value >> 8) & 0xFF) / 255,
        a: CGFloat(value & 0xFF) / 255
    )
}
