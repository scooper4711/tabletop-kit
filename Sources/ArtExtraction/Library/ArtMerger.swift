import CoreGraphics
import Foundation

/// Merges the art found in one PDF into the library: each painting once, with every product that prints it. Art
/// with the same name is the same painting when its images match, or, when one of them is a figure (a Battle
/// Card's creature is the pawn box's painting cut differently), when its colors match (`Figure.palette`).
struct ArtMerger {
    let library: ArtLibrary
    let prepared: PreparedArt
    let source: ArtSource
    private let document: CGPDFDocument?
    private var pages: [Int: [ImagePlacement]] = [:]

    init(library: ArtLibrary, prepared: PreparedArt, source: ArtSource) {
        self.library = library
        self.prepared = prepared
        self.source = source
        document = CGPDFDocument(prepared.file as CFURL)
    }

    mutating func merge(_ found: ExtractedPawn, into report: inout ArtImportReport) throws {
        guard !found.name.isEmpty else {
            report.unnamed += 1
            return
        }
        let print = try makePrint(of: found)
        let candidates = library.entries.indices.filter { index in
            library.entries[index].game == source.game
                && Self.key(library.entries[index].name) == Self.key(found.name)
        }
        if let index = candidates.first(where: { library.entries[$0].fingerprint.matches(found.fingerprint) })
            ?? samePainting(as: found, print: print, among: candidates) {
            add(print, of: found, to: index)
            report.alreadyKnown += 1
        } else {
            library.entries.append(ArtEntry(id: UUID(), name: found.name, game: source.game, size: found.size,
                                            traits: found.traits, fingerprint: found.fingerprint, prints: [print],
                                            palette: []))
            report.added += 1
        }
    }

    /// Names compared without case or accents.
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private func add(_ print: ArtPrint, of found: ExtractedPawn, to index: Int) {
        var entry = library.entries[index]
        guard !entry.prints.contains(where: { $0.sourceID == print.sourceID && $0.face == print.face }) else { return }
        entry.prints.append(print)
        // Figures first, as they are the sharpest; otherwise in the order the products were added.
        entry.prints = entry.prints.enumerated().sorted { first, second in
            first.element.kind == second.element.kind ? first.offset < second.offset
                                                      : first.element.kind < second.element.kind
        }.map(\.element)
        entry.traits += found.traits.filter { !entry.traits.contains($0) }
        if print.kind == .pawn { entry.size = found.size }
        library.entries[index] = entry
    }

    /// The entry among `candidates` showing the same painting by its colors, when either is a figure.
    private mutating func samePainting(as found: ExtractedPawn, print: ArtPrint, among candidates: [Int]) -> Int? {
        let involved = candidates.filter { index in
            print.kind == .figure || library.entries[index].prints.contains { $0.kind == .figure }
        }
        guard print.kind != .token, !involved.isEmpty, let figure = figure(of: print) else { return nil }
        let palette = figure.palette()
        return involved.first { index in
            let known = library.palette(of: index)
            return !known.isEmpty && Figure.paletteDistance(palette, known) <= Figure.samePaintingDistance
        }
    }

    private mutating func figure(of print: ArtPrint) -> Figure? {
        guard let document else { return nil }
        if pages[print.face.pageIndex] == nil {
            pages[print.face.pageIndex] = document.page(at: print.face.pageIndex + 1).map(PageScanner.images(on:))
        }
        return ArtLibrary.figure(of: print, among: pages[print.face.pageIndex] ?? [])
    }

    /// Where the found art is printed; a token's art, drawn alone at import, is kept as a picture.
    private func makePrint(of found: ExtractedPawn) throws -> ArtPrint {
        switch found.shape {
        case .pawn:
            return ArtPrint(sourceID: source.id, kind: .pawn, face: found.front, copies: found.copies)
        case .card(let imageIndex):
            return ArtPrint(sourceID: source.id, kind: .figure, face: found.front, imageIndex: imageIndex,
                            copies: found.copies)
        case .token(let pictures):
            let file = "\(UUID().uuidString).png"
            do {
                try pictures.front.write(to: library.tokenURL(file))
            } catch {
                throw ArtLibraryError.saveFailed("writing a token's art: \(error.localizedDescription)")
            }
            return ArtPrint(sourceID: source.id, kind: .token, face: found.front, tokenFile: file, copies: found.copies)
        }
    }
}
