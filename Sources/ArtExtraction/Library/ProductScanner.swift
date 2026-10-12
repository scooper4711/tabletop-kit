import Foundation

/// Finds the PDFs that print creature art in a folder of Paizo downloads, such as Scrollkeeper's.
public enum ProductScanner {
    /// PDFs under `folder` whose name mentions pawns or tokens, decks of Battle Cards and item decks, each deck
    /// once as its art PDF, and the folders of item decks printed as pictures, sorted by name.
    public static func artPDFs(in folder: URL) -> [URL] {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        var pdfs: [URL] = []
        var pictureFolders: Set<URL> = []
        for file in files where ["jpg", "jpeg"].contains(file.pathExtension.lowercased())
            && pictureFolders.insert(file.deletingLastPathComponent()).inserted {
            if let deck = ImageDeck.containing(file) { pdfs.append(deck.folder) }
        }
        for file in files where file.pathExtension.lowercased() == "pdf" {
            if let deck = CardDeck.containing(file) {
                if !pdfs.contains(deck.artFile) { pdfs.append(deck.artFile) }
            } else if ["pawn", "token"].contains(where: file.lastPathComponent.localizedCaseInsensitiveContains) {
                pdfs.append(file)
            }
        }
        return pdfs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
