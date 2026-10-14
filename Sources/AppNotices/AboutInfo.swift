import Foundation

/// What an app's About screen shows: the notices Paizo requires, and what differs from app to app.
public struct AboutInfo: Sendable {
    /// The line the Paizo Compatibility License requires.
    public static let trademarkNotice =
        "Pathfinder and Starfinder are registered trademarks and copyrights of Paizo Inc."
    // Literal URLs that are known to parse.
    // swiftlint:disable force_unwrapping
    public static let policyURL = URL(string: "https://paizo.com/licenses/communityuse")!
    public static let paizoURL = URL(string: "https://paizo.com")!
    // swiftlint:enable force_unwrapping

    public let appName: String
    /// One line saying what the app is.
    public let tagline: String
    /// One line for each kind of third-party content the app ships, with its license.
    public let credits: [String]
    /// Where to reach the author, which the Community Use Policy requires.
    public let contactURL: URL

    public init(appName: String, tagline: String, credits: [String], contactURL: URL) {
        self.appName = appName
        self.tagline = tagline
        self.credits = credits
        self.contactURL = contactURL
    }

    /// The notice the Community Use Policy prescribes. Its wording is fixed; only the product name is ours.
    public var communityUseNotice: String {
        "\(appName) uses trademarks and/or copyrights owned by Paizo Inc., used under Paizo's Community Use "
            + "Policy (paizo.com/licenses/communityuse). We are expressly prohibited from charging you to use or "
            + "access this content. \(appName) is not published, endorsed, or specifically approved by Paizo. For "
            + "more information about Paizo Inc. and Paizo products, visit paizo.com."
    }

    /// Everything the screen shows, as plain text with the links written out, for the Mac's About panel.
    public var panelText: String {
        let paragraphs = [tagline, communityUseNotice, Self.trademarkNotice] + credits
            + ["Contact: \(contactURL.absoluteString)"]
        return paragraphs.joined(separator: "\n\n")
    }
}
