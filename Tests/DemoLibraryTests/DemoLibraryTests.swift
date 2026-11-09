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
