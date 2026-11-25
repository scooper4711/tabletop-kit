import Foundation

/// The license a source book's game text is used under: the ORC License, the Open Game License 1.0a, or neither
/// (such as content used only under the Paizo–Foundry agreement, which doesn't extend to the toolkit apps).
public enum SourceLicense: String, Codable, Hashable, Sendable {
    case orc, ogl, none
}

/// One source book in the catalog: what its notice says and where that was checked.
///
/// An entry either quotes its notice whole (`notice`, as the seed from pf2e's license files does) or gives the
/// facts to build one from (`year`, `publisher`, `credits`). Facts that are missing make the entry a gap: an import
/// that uses it fails until someone fills them in by hand (see `docs/source-attribution-gaps.md`).
public struct CatalogEntry: Hashable, Sendable {
    public struct Credit: Codable, Hashable, Sendable {
        public var role: String
        public var names: [String]

        public init(role: String, names: [String]) {
            self.role = role
            self.names = names
        }
    }

    public var title: String
    public var aliases: [String] = []
    public var game: String = ""
    public var license: SourceLicense?
    public var notice: String?
    public var year: Int?
    public var publisher: String?
    public var credits: [Credit] = []
    /// Notices of earlier works the source's own copyright notice carries, such as a creature from the
    /// Tome of Horrors Complete; the OGL's Section 15 has to repeat them.
    public var includes: [String] = []
    public var reference: String?
    /// False while the facts come from somewhere other than the book's own notice and nobody has checked them.
    public var verified: Bool = true
    public var note: String?

    public init(title: String) {
        self.title = title
    }

    /// The facts the entry still lacks, by name; empty when it can be attributed.
    public var missingFacts: [String] {
        var missing: [String] = []
        if license == nil { missing.append("license") }
        guard notice == nil else { return missing }
        if year == nil { missing.append("year") }
        if publisher?.isEmpty ?? true { missing.append("publisher") }
        if credits.allSatisfy({ $0.names.isEmpty }) { missing.append("credits") }
        return missing
    }

    /// The line the notice lists: the quoted notice, or one built the way Paizo writes them,
    /// `Title © 2023, Paizo Inc.; Authors: A, B, and C.`
    public var noticeLine: String {
        if let notice { return notice }
        let credited = credits.filter { !$0.names.isEmpty }.map { "\($0.role): \(Self.list($0.names))" }
        let head = "\(title) © \(year.map(String.init) ?? "?"), \(publisher ?? "?")"
        return ([head] + credited).joined(separator: "; ") + "."
    }

    private static func list(_ names: [String]) -> String {
        guard names.count > 2, let last = names.last else { return names.joined(separator: " and ") }
        return names.dropLast().joined(separator: ", ") + ", and " + last
    }
}

extension CatalogEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case title, aliases, game, license, notice, year, publisher, credits, includes, reference, verified, note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        game = try container.decodeIfPresent(String.self, forKey: .game) ?? ""
        license = try container.decodeIfPresent(SourceLicense.self, forKey: .license)
        notice = try container.decodeIfPresent(String.self, forKey: .notice)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        credits = try container.decodeIfPresent([Credit].self, forKey: .credits) ?? []
        includes = try container.decodeIfPresent([String].self, forKey: .includes) ?? []
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        verified = try container.decodeIfPresent(Bool.self, forKey: .verified) ?? true
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}
