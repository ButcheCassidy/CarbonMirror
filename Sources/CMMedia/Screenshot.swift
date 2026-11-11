import Foundation

/// Where Mac screenshots of the phone go (spec A7): `~/Pictures/CarbonMirror/`, the only folder outside the
/// app's container it may write to, named `CarbonMirror-YYYY-MM-DD-HHmmss.png`.
public enum ScreenshotLocation {
    public static let folderName = "CarbonMirror"

    /// File name for a screenshot taken at `date` (local time).
    public static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ v: Int?) -> String { String(format: "%02d", v ?? 0) }
        return "CarbonMirror-\(c.year ?? 0)-\(two(c.month))-\(two(c.day))-\(two(c.hour))\(two(c.minute))\(two(c.second)).png"
    }

    /// `~/Pictures/CarbonMirror/` (inside the sandbox this resolves through the Pictures entitlement).
    public static func folder() -> URL? {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.appendingPathComponent(folderName, isDirectory: true)
    }
}
