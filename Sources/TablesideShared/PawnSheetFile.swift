import Foundation

/// A request written as one of Pawn Shop's sheet files (R6.5), for where a link can't open a document: the app
/// shares the file, and Pawn Shop opens it as it opens any sheet.
extension PawnSheetRequest {
    /// The type of Pawn Shop's sheet files, which Pawn Shop declares, and their extension.
    public static let sheetFileType = "io.github.scooper4711.pawnsheet"
    public static let sheetFileExtension = "pawnsheet"
    /// The sheet format the file is written in: 2, the first in which a sheet may leave its settings to Pawn Shop.
    public static let sheetFileFormatVersion = 2

    /// The contents of the sheet file: an entry per line that asks for a pawn, with its count, the pawn's ID and
    /// the creature's name, so Pawn Shop shows the pawn where its library has it and a named placeholder where it
    /// doesn't. A line that names no pawn gets an ID of its own. The file holds no settings: Pawn Shop gives the
    /// sheet those of a new one.
    /// - Parameter readerVersion: The version of the PDF reader behind the sender's library, when it knows it.
    public func sheetFile(readerVersion: Int? = nil) -> Data {
        let entries = lines.filter { $0.count >= 1 }.map { line in
            let pawnID = line.pawnID ?? UUID()
            return SheetFileContents.Entry(id: UUID(), pawnID: pawnID, count: line.count,
                                           label: .init(id: pawnID, name: line.name, product: ""))
        }
        let contents = SheetFileContents(formatVersion: Self.sheetFileFormatVersion, readerVersion: readerVersion,
                                         entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Strings, numbers and UUIDs always encode.
        // swiftlint:disable:next force_try
        return try! encoder.encode(contents)
    }

    /// A name for the sheet file: the title without what a file's name can't hold, or "Pawns" when nothing is
    /// left, and the extension. Pawn Shop names the sheet after its file.
    public var sheetFileName: String {
        let words = title.components(separatedBy: Self.unfitForFileNames)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
        var name = words.joined(separator: " ")
        while name.hasPrefix(".") { name.removeFirst() }
        name = String(name.prefix(Self.longestFileName)).trimmingCharacters(in: .whitespaces)
        return "\(name.isEmpty ? "Pawns" : name).\(Self.sheetFileExtension)"
    }

    private static let unfitForFileNames = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        .union(.newlines)
    private static let longestFileName = 100
}

/// The keys of a sheet file that a request fills: the same ones Pawn Shop writes (its spec, R12).
private struct SheetFileContents: Encodable {
    var formatVersion: Int
    var readerVersion: Int?
    var entries: [Entry]

    struct Entry: Encodable {
        var id: UUID
        var pawnID: UUID
        var count: Int
        var label: Label
    }

    /// What Pawn Shop calls a pawn its library lacks: `ArtReference`'s keys.
    struct Label: Encodable {
        var id: UUID
        var name: String
        var product: String
    }
}
