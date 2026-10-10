import BattleCards
import Foundation

/// `CardArtImport PACKS_FOLDER OUTPUT_FOLDER`
///
/// Copies the battle cards' UI art from the user's Rexard packs (as Humble Bundle's downloads unpack) into an app's
/// folder, such as `Generated/CardArt`. Missing pieces are listed; the cards draw them as plain color.
let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2, let packs = arguments.first, let output = arguments.last else {
    FileHandle.standardError.write(Data("Usage: CardArtImport PACKS_FOLDER OUTPUT_FOLDER\n".utf8))
    exit(2)
}
do {
    let missing = try CardArtCopier.copy(from: URL(fileURLWithPath: packs), to: URL(fileURLWithPath: output))
    let copied = CardArtPieces.manifest.count - missing.count
    print("Copied \(copied) of \(CardArtPieces.manifest.count) pieces of card art.")
    for piece in missing { print("  Missing \(piece.packPath) (\(piece.name))") }
} catch {
    FileHandle.standardError.write(Data("Copying the card art failed: \(error)\n".utf8))
    exit(1)
}
