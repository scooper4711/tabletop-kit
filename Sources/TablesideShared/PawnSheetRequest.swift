import Foundation

/// Why a link couldn't be read as a pawn sheet request.
public enum PawnSheetRequestError: Error, Equatable, LocalizedError {
    /// The link isn't a sheet request: another scheme or host.
    case unrecognizedLink
    /// The link is a sheet request whose payload is missing or damaged.
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .unrecognizedLink: "Reading the pawn sheet request failed: the link isn't one."
        case .unreadable: "Reading the pawn sheet request failed: its list of pawns can't be read."
        }
    }
}

/// What another toolkit app asks Pawn Shop to put on a new sheet (R6): a title and the pawns to print, sent as a
/// `pawnshop://sheet?request=…` link.
public struct PawnSheetRequest: Codable, Equatable, Sendable {
    public static let scheme = "pawnshop"
    static let host = "sheet"
    static let payloadName = "request"

    /// The bare link, which carries no request: for asking whether anything installed takes these links.
    public static var probeURL: URL { components().url! }

    /// One kind of pawn on the sheet.
    public struct Line: Codable, Equatable, Sendable {
        /// The creature's name, shown where Pawn Shop has no pawn for it.
        public var name: String
        public var count: Int
        /// The pawn meant: its art's ID in the shared library, or a custom creature's ID. Nil when the sender
        /// knows of none.
        public var pawnID: UUID?

        public init(name: String, count: Int = 1, pawnID: UUID? = nil) {
            self.name = name
            self.count = count
            self.pawnID = pawnID
        }
    }

    /// What to call the sheet.
    public var title: String
    public var lines: [Line]

    public init(title: String, lines: [Line]) {
        self.title = title
        self.lines = lines
    }

    /// Reads the request a link carries.
    public init(url: URL) throws(PawnSheetRequestError) {
        guard url.scheme?.lowercased() == Self.scheme, url.host?.lowercased() == Self.host else {
            throw .unrecognizedLink
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let payload = items.first(where: { $0.name == Self.payloadName })?.value,
              let data = Self.data(fromURLSafeBase64: payload),
              let request = try? JSONDecoder().decode(Self.self, from: data)
        else { throw .unreadable }
        self = request
    }

    /// The link that carries the request. The same request always gives the same link.
    public var url: URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Strings, numbers and UUIDs always encode.
        // swiftlint:disable:next force_try
        let payload = Self.urlSafeBase64(try! encoder.encode(self))
        var components = Self.components()
        components.queryItems = [URLQueryItem(name: Self.payloadName, value: payload)]
        return components.url!
    }

    private static func components() -> URLComponents {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        return components
    }

    /// Base64 with `-` and `_` and no padding, so nothing in it needs escaping in a link.
    private static func urlSafeBase64(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func data(fromURLSafeBase64 text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
