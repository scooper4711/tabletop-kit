import ArtExtraction
import CoreGraphics
import Foundation

/// A picture to draw after a PDF's art is written, from one of its prints.
struct PictureJob: Equatable {
    var print: SharedPrint
}

/// Merges the art found in one PDF into the shared library, inside one write, as `ArtMerger` does for
/// `ArtLibrary`: by key first (R2.5); else, among art with the same folded name, game and kind (item or
/// creature), by matching fingerprint or, when one is a figure, matching colors (`Figure.palette`).
struct StoreMerger {
    let writer: LibraryWriter
    let library: SharedLibrary
    let source: ArtSource
    /// The pictures to draw once the write is done.
    private(set) var pictures: [PictureJob] = []
    private let document: CGPDFDocument?
    private var pages: [Int: [ImagePlacement]] = [:]
    /// The game's named creature art, read once when nameless art looks for its name (`StoreMerger+Nameless`).
    var namedCreatures: [SharedArtEntry]?
    /// The IDs of the sources from products that print no names, read once when needed.
    var namelessSources: Set<String>?

    init(writer: LibraryWriter, library: SharedLibrary, source: ArtSource, file: URL) {
        self.writer = writer
        self.library = library
        self.source = source
        document = CGPDFDocument(file as CFURL)
    }

    /// Merges each piece of art the PDF prints, but items printed without a name (R2.3a).
    mutating func merge(_ found: [ExtractedPawn], into report: inout ArtImportReport) throws {
        let kept = found.filter { !$0.name.isEmpty || !Self.isItem($0) }
        report.unnamed += found.count - kept.count
        let keys = ArtKey.keys(for: kept.map { pawn in
            ArtKeyInput(sourceID: source.id, name: pawn.name, size: pawn.size, fingerprint: pawn.fingerprint,
                        face: pawn.front)
        })
        for (pawn, key) in zip(kept, keys) { try merge(pawn, key: key, into: &report) }
    }

    // MARK: Helpers

    private mutating func merge(_ found: ExtractedPawn, key: UUID, into report: inout ArtImportReport) throws {
        let print = try makePrint(of: found, key: key)
        var entry = try placed(found, print: print, into: &report)
        let drawsPicture = entry.picture == nil || (print.print.kind == .figure && !isDrawnFromFigure(entry))
        if drawsPicture, let kept = print.print.tokenFile { entry.picture = kept }
        try writer.merge(entry)
        if drawsPicture, print.print.tokenFile == nil { pictures.append(PictureJob(print: print)) }
    }

    /// The entry `found` joins, or a new one, counted in `report`.
    private mutating func placed(_ found: ExtractedPawn, print: SharedPrint,
                                 into report: inout ArtImportReport) throws -> SharedArtEntry {
        if let known = try entry(withKey: print.key) {
            report.alreadyKnown += 1
            return joined(print, of: found, to: known)
        }
        if found.name.isEmpty { return try placedNameless(found, print: print, into: &report) }
        if let known = try sameArt(as: found, print: print) ?? waitingForName(sameArtAs: found) {
            report.alreadyKnown += 1
            return joined(print, of: found, to: known)
        }
        report.added += 1
        return newEntry(found, print: print)
    }

    private static func isItem(_ found: ExtractedPawn) -> Bool {
        switch found.shape {
        case .item, .drawnItem: true
        case .pawn, .card, .token: false
        }
    }

    private func makePrint(of found: ExtractedPawn, key: UUID) throws -> SharedPrint {
        let file = try found.keptPicture.map { try save($0, as: "\(key.uuidString).png", of: found) }
        var backPicture: String?
        if case .token(let pictures) = found.shape, let back = pictures.back {
            backPicture = try save(back, as: "\(key.uuidString)-back.png", of: found)
        }
        let back: PawnFace? = found.shape == .pawn ? found.back : nil
        return SharedPrint(key: key, print: ArtPrint(found: found, sourceID: source.id, pictureFile: file), back: back,
                           backPicture: backPicture)
    }

    /// Writes a picture drawn at import into the `Pictures` folder, returning its name there.
    private func save(_ png: Data, as file: String, of found: ExtractedPawn) throws -> String {
        do {
            try png.write(to: library.pictureFile(file), options: .atomic)
        } catch {
            throw SharedLibraryError(operation: "Saving \(found.name)'s picture", detail: error.localizedDescription)
        }
        return file
    }

    func entry(withKey key: UUID) throws -> SharedArtEntry? {
        try ArtRows.entries(in: writer.database, where: "id IN (SELECT entry FROM prints WHERE key = ?)",
                            [.text(key.uuidString)]).first
    }

    /// Art of the same name showing the same picture: matching fingerprints, or colors when one is a figure, whose
    /// name may then give more or less of the creature's family (`CreatureName.matches`).
    private mutating func sameArt(as found: ExtractedPawn, print: SharedPrint) throws -> SharedArtEntry? {
        let isItem = print.print.kind == .item
        let candidates = try ArtRows.entries(in: writer.database, where: "foldedName = ? AND game = ?",
                                             [.text(ArtKey.foldedName(found.name)), .text(source.game.rawValue)])
            .filter { $0.artEntry.isItem == isItem }
        if let match = candidates.first(where: { isSameImage($0, found, print: print) }) { return match }
        let involved = try (candidates + family(of: found, isItem: isItem, besides: candidates)).filter { candidate in
            print.print.kind == .figure || candidate.prints.contains { $0.print.kind == .figure }
        }
        guard print.print.kind != .token, !involved.isEmpty, let figure = figure(of: print.print) else { return nil }
        let palette = figure.palette()
        for candidate in involved {
            let known = try self.palette(of: candidate)
            if !known.isEmpty, Figure.paletteDistance(palette, known) <= Figure.samePaintingDistance {
                return candidate
            }
        }
        return nil
    }

    /// True when `found` shows `candidate`'s images. A Battle Card's picture and a pawn's are compared as paintings,
    /// by their colors, so between them only the same images count: their thumbnails look alike for any two
    /// paintings of one shape.
    private func isSameImage(_ candidate: SharedArtEntry, _ found: ExtractedPawn, print: SharedPrint) -> Bool {
        let involvesFigure = print.print.kind == .figure || candidate.prints.contains { $0.print.kind == .figure }
        guard involvesFigure else { return candidate.fingerprint.matches(found.fingerprint) }
        return !found.fingerprint.imageDigests.isEmpty
            && candidate.fingerprint.imageDigests == found.fingerprint.imageDigests
    }

    /// Named art of the same family as `found` under another name, such as "Devil, Imp" for "Imp".
    private func family(of found: ExtractedPawn, isItem: Bool,
                        besides known: [SharedArtEntry]) throws -> [SharedArtEntry] {
        guard !isItem else { return [] }
        let ids = Set(known.map(\.id))
        return try ArtRows.entries(in: writer.database, where: "nameKey = ? AND game = ? AND needsName = 0",
                                   [.text(CreatureName.familyKey(found.name)), .text(source.game.rawValue)])
            .filter { !ids.contains($0.id) && !$0.artEntry.isItem && CreatureName.matches($0.name, found.name) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// `known` with `print` added; art waiting for a name takes `found`'s.
    func joined(_ print: SharedPrint, of found: ExtractedPawn, to known: SharedArtEntry) -> SharedArtEntry {
        var entry = known
        if entry.needsName && !found.name.isEmpty {
            entry.name = found.name
            entry.needsName = false
        }
        entry.prints.removeAll { known in
            known.print.sourceID == source.id && (known.key == print.key || known.print.face == print.print.face)
        }
        entry.prints.append(print)
        entry.traits += found.traits.filter { !entry.traits.contains($0) }
        if print.print.kind == .pawn { entry.size = found.size }
        return entry
    }

    func newEntry(_ found: ExtractedPawn, print: SharedPrint) -> SharedArtEntry {
        let art = ArtEntry(id: print.key, name: found.name, game: source.game, size: found.size, traits: found.traits,
                           fingerprint: found.fingerprint, prints: [], palette: [])
        var entry = SharedArtEntry(art, keys: [])
        entry.prints = [print]
        return entry
    }

    /// True when the entry's picture is drawn from one of its figures, the sharpest kind of print.
    private func isDrawnFromFigure(_ entry: SharedArtEntry) -> Bool {
        entry.prints.contains { $0.print.kind == .figure && entry.picture?.hasPrefix($0.key.uuidString) == true }
    }

    /// The entry's colors, measured once from a print this app can draw and kept with it.
    private func palette(of entry: SharedArtEntry) throws -> [Double] {
        if !entry.palette.isEmpty { return entry.palette }
        for print in entry.prints where print.print.kind != .token {
            guard let figure = library.figure(of: print.print) else { continue }
            let palette = figure.palette()
            try writer.database.run("UPDATE art SET palette = ?, changed = ? WHERE id = ?",
                                    [try ArtRows.encoded(palette), .integer(writer.counter),
                                     .text(entry.id.uuidString)])
            return palette
        }
        return []
    }

    /// The figure a print in this PDF shows.
    private mutating func figure(of print: ArtPrint) -> Figure? {
        guard let document else { return nil }
        if pages[print.face.pageIndex] == nil {
            pages[print.face.pageIndex] = document.page(at: print.face.pageIndex + 1).map(PageScanner.images(on:))
        }
        return ArtLibrary.figure(of: print, among: pages[print.face.pageIndex] ?? [])
    }
}
