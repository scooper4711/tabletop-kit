import Foundation

/// A product's readable title, from the name Paizo gives its download.
public enum ProductTitle {
    /// "PZO1234 Pathfinder Pawns- Bestiary Box PDF.pdf" becomes "Pathfinder Pawns: Bestiary Box".
    public static func fromFileName(_ name: String) -> String {
        var title = (name as NSString).deletingPathExtension
        title = title.replacingOccurrences(of: #"^PZO\w+\s+"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\s+PDF$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return title.replacingOccurrences(of: "- ", with: ": ")
    }
}
