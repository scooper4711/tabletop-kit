import ArtExtraction
import ArtExtractionTestSupport
@testable import DemoLibrary
import Foundation
import PDFKit
import Testing

/// The demo library's PDFs, read as the toolkit apps read them (R3).
@Suite final class DemoLibraryTests {
    private let folder = temporaryFolder()
    private var written: URL { folder.appendingPathComponent("written") }

    init() throws {
        try DemoLibrary.write(to: written)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The art products copied to the names Scrollkeeper gives its demo downloads.
    private func downloads() throws -> URL {
        let downloads = folder.appendingPathComponent("Files")
        let names: [DemoLibrary.File: String] = [
            .pawnCollection: "Sample Bestiary Pawn Collection/Sample Bestiary Pawn Collection PDF.pdf",
            .heroPawns: "Sample Iconic Heroes Pawn Collection/Sample Iconic Heroes Pawn Collection PDF.pdf",
            .tokenSet: "Sample Bestiary Token Set/Sample Bestiary Token Set PDF.pdf",
            .battleCards: "Sample Bestiary Battle Cards/Sample Bestiary Battle Cards PDF.pdf",
            .adventure: "Sample Adventure/Sample Adventure PDF.pdf"
        ]
        for (file, name) in names {
            let target = downloads.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: written.appendingPathComponent(file.rawValue), to: target)
        }
        return downloads
    }

    @Test func writesEveryFileEndingWithTheNotice() throws {
        for file in DemoLibrary.File.allCases {
            let document = try #require(PDFDocument(url: written.appendingPathComponent(file.rawValue)), "\(file)")
            let last = document.page(at: document.pageCount - 1)?.string ?? ""
            #expect(last.contains("Scrollkeeper's demo library"), "\(file)")
            #expect(last.contains("Community Use Policy"), "\(file)")
        }
    }

    /// Each map is a page the size of a Flip-Mat, 24 by 30 inches, then the letter-size notice.
    @Test func theMapsAreFlipMatSize() throws {
        for file in [DemoLibrary.File.forestMap, .starshipMap] {
            let document = try #require(PDFDocument(url: written.appendingPathComponent(file.rawValue)), "\(file)")
            #expect(document.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 24 * 72, height: 30 * 72),
                    "\(file)")
            #expect(document.page(at: 1)?.bounds(for: .mediaBox).size == CGSize(width: 612, height: 792), "\(file)")
        }
    }

    @Test func eachFilesNoticeSaysWhatItHoldsAndOnlyProseMentionsLoremIpsum() throws {
        let contents: [DemoLibrary.File: DemoNotice.Content] = [
            .pawnCollection: .drawnCreatures, .heroPawns: .iconicPawns, .tokenSet: .drawnCreatures,
            .battleCards: .drawnCreatures, .forestMap: .drawnMaps, .starshipMap: .drawnMaps,
            .adventure: .placeholderProse, .scenario: .placeholderProse, .rulebook: .placeholderProse
        ]
        for file in DemoLibrary.File.allCases {
            let document = try #require(PDFDocument(url: written.appendingPathComponent(file.rawValue)), "\(file)")
            let content = try #require(contents[file], "\(file)")
            let last = Self.words(document.page(at: document.pageCount - 1)?.string ?? "")
            #expect(last.contains(Self.words(content.sentence)), "\(file)")
            let mentionsLorem = (document.string ?? "").localizedCaseInsensitiveContains("lorem ipsum")
            #expect(mentionsLorem == (content == .placeholderProse), "\(file)")
        }
    }

    @Test func theHandoutIsATornMapFragmentDrawnTheSameEveryTime() throws {
        let fragment = try #require(DemoMaps.fragment())
        let again = try #require(DemoMaps.fragment())
        #expect(fragment.dataProvider?.data == again.dataProvider?.data)
        // The torn edge leaves the corners clear, and the middle is the map.
        let pixels = try #require(fragment.dataProvider?.data as Data?)
        let alpha = { (column: Int, row: Int) in pixels[row * fragment.bytesPerRow + column * 4 + 3] }
        #expect(alpha(0, 0) == 0 && alpha(fragment.width - 1, fragment.height - 1) == 0)
        #expect(alpha(fragment.width / 2, fragment.height / 2) == 255)
        let adventure = try #require(PDFDocument(url: written.appendingPathComponent("adventure.pdf")))
        #expect(adventure.page(at: 2)?.string?.contains("Handout: The Map Fragment") == true)
    }

    /// The text with its line breaks and runs of spaces made single spaces, as a page's text wraps it.
    private static func words(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    @Test func writingAgainGivesTheSameFiles() throws {
        let again = folder.appendingPathComponent("again")
        try DemoLibrary.write(to: again)
        for file in DemoLibrary.File.allCases {
            let first = try Data(contentsOf: written.appendingPathComponent(file.rawValue))
            #expect(first == (try Data(contentsOf: again.appendingPathComponent(file.rawValue))), "\(file)")
            #expect(PDFDocument(data: first) != nil, "\(file)")
        }
    }

    @Test func theArtImportFindsEveryArtProduct() throws {
        let found = ProductScanner.artPDFs(in: try downloads()).map(\.lastPathComponent)
        #expect(found == ["Sample Bestiary Battle Cards PDF.pdf", "Sample Bestiary Pawn Collection PDF.pdf",
                          "Sample Bestiary Token Set PDF.pdf", "Sample Iconic Heroes Pawn Collection PDF.pdf"])
    }

    @Test func theArtImportNamesEveryMonster() throws {
        let monsters = Set(DemoArtProducts.monsters.map(\.name))
        for file in [DemoLibrary.File.pawnCollection, .tokenSet, .battleCards] {
            let library = try ArtLibrary(folder: folder.appendingPathComponent("Library-\(file.rawValue)"))
            let kind: [DemoLibrary.File: String] = [.pawnCollection: "Pawn", .tokenSet: "Token",
                                                    .battleCards: "Battle Cards"]
            let copy = folder.appendingPathComponent("Sample Bestiary \(kind[file] ?? "") \(UUID()).pdf")
            try FileManager.default.copyItem(at: written.appendingPathComponent(file.rawValue), to: copy)
            try library.add(copy, keeping: true)
            let names = Set(library.entries.map(\.name))
            #expect(monsters.isSubset(of: names), "\(file): \(monsters.subtracting(names).sorted()) missing")
        }
    }

    @Test func theMonsterPawnsAreReadByTheirOutlines() throws {
        let copy = folder.appendingPathComponent("Sample Bestiary Pawn Collection.pdf")
        try FileManager.default.copyItem(at: written.appendingPathComponent(DemoLibrary.File.pawnCollection.rawValue),
                                         to: copy)
        let pawns = try PawnExtractor.extract(from: copy).pawns
        #expect(pawns.count == DemoArtProducts.monsters.count)
        #expect(pawns.allSatisfy { !$0.name.contains("©") })
        let sizes = Dictionary(uniqueKeysWithValues: pawns.map { ($0.name, $0.size) })
        #expect(sizes["Owlbear"] == .large && sizes["Goblin Warrior"] == .small && sizes["Wolf"] == .medium)
    }

    @Test func theArtImportNamesTheHeroes() throws {
        let library = try ArtLibrary(folder: folder.appendingPathComponent("Library-heroes"))
        let copy = folder.appendingPathComponent("Sample Iconic Heroes Pawn Collection.pdf")
        try FileManager.default.copyItem(at: written.appendingPathComponent(DemoLibrary.File.heroPawns.rawValue),
                                         to: copy)
        try library.add(copy, keeping: true)
        let heroes = Set(DemoArt(communityUseFolder: nil).iconics.prefix(8).map(\.name))
        #expect(heroes.isSubset(of: Set(library.entries.map(\.name))))
    }
}
