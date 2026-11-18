import Foundation

/// A monetary value stored as an integer in the currency's smallest unit.
/// VND has no fractional subunit, so 1,250,000 VND is stored as 1_250_000.
public struct MoneyAmount: Equatable, Hashable, Sendable {
    public let minorUnits: Int64
    public let currencyCode: String

    public init(minorUnits: Int64, currencyCode: String = "VND") {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode.uppercased()
    }

    /// A deterministic display string using Vietnamese thousands separators.
    /// This formatter never converts the amount to Double.
    public var formatted: String {
        let digits = Array(String(minorUnits.magnitude))
        let firstGroupLength = digits.count % 3
        var groups: [String] = []

        if firstGroupLength > 0 {
            groups.append(String(digits[..<firstGroupLength]))
        }

        var index = firstGroupLength
        while index < digits.count {
            groups.append(String(digits[index..<(index + 3)]))
            index += 3
        }

        let sign = minorUnits < 0 ? "−" : ""
        let suffix = currencyCode == "VND" ? "₫" : currencyCode
        return sign + groups.joined(separator: ".") + " " + suffix
    }
}
