import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ArtExtraction
import ArtExtractionTestSupport

@Suite struct TokenExtractionTests {
    @Test func namesATokenFromTheNameAlongItsRim() throws {
        let token = DrawnToken(center: CGPoint(x: 100, y: 600), rimName: "SMOG SCAMP 2")
        let result = try extractTokens([[token]])
        let pawn = try #require(result.pawns.first)
        #expect(result.pawns.count == 1 && result.unnamed.isEmpty)
        #expect(pawn.name == "Smog Scamp 2" && pawn.size == .medium)
        guard case .token(let pictures) = pawn.shape else { Issue.record("not a token"); return }
        #expect(pictures.back == nil && pawn.back == pawn.front.mirroredCopy())
        #expect(abs(pawn.front.rect.width - 90) < 1)
    }

    @Test func namesTokensFromTheirLabelsOnTheBackPage() throws {
        let fronts = [DrawnToken(center: CGPoint(x: 100, y: 600)),
                      DrawnToken(center: CGPoint(x: 200, y: 600), art: tokenArt(variant: 1))]
        var backs = fronts.map { $0.mirrored(pageWidth: letterPage.width) }
        backs[0].art = darkBackground()
        backs[0].label = ["3", "AEON GUARD,", "SPECIALIST", "© 2026 PAIZO INC."]
        backs[1].art = darkBackground()
        backs[1].label = ["12", "AKATA", "© 2026 PAIZO INC."]
        let result = try extractTokens([fronts, backs])
        #expect(result.pawns.map(\.name) == ["Aeon Guard, Specialist", "Akata"])
        #expect(result.pawns.allSatisfy { $0.back == $0.front.mirroredCopy() })
    }

    @Test func takesTheBackFromADuplexPageRepeatingTheArt() throws {
        let front = DrawnToken(center: CGPoint(x: 100, y: 600), rimName: "NITPICK")
        let result = try extractTokens([[front], [front.mirrored(pageWidth: letterPage.width)]])
        let pawn = try #require(result.pawns.first)
        #expect(result.pawns.count == 1 && pawn.name == "Nitpick")
        #expect(pawn.back.pageIndex == 1 && !pawn.back.mirrored)
        guard case .token(let pictures) = pawn.shape else { Issue.record("not a token"); return }
        #expect(pictures.back != nil)
    }

    @Test func countsCopiesAndSizesTokensByTheirCut() throws {
        let tokens = [DrawnToken(center: CGPoint(x: 100, y: 600), rimName: "OGRE"),
                      DrawnToken(center: CGPoint(x: 200, y: 600), rimName: "OGRE"),
                      DrawnToken(center: CGPoint(x: 150, y: 400), diameter: 162, rimName: "GIANT"),
                      DrawnToken(center: CGPoint(x: 400, y: 300), diameter: 232, rimName: "DRAGON")]
        let result = try extractTokens([tokens])
        #expect(result.pawns.map(\.copies) == [2, 1, 1])
        #expect(result.pawns.map(\.size) == [.medium, .large, .huge])
    }

    @Test func reportsTokensWithoutANameAndIgnoresBadgesAndCoverArt() throws {
        let tokens = [DrawnToken(center: CGPoint(x: 100, y: 600)),
                      DrawnToken(center: CGPoint(x: 300, y: 700), diameter: 20, rimName: "BADGE"),
                      DrawnToken(center: CGPoint(x: 306, y: 300), diameter: 400, rimName: "COVER")]
        let result = try extractTokens([tokens])
        #expect(result.pawns.count == 1 && result.pawns[0].name.isEmpty)
        #expect(result.unnamed.count == 1)
    }

    @Test func leavesThePageBackgroundAndPrintedNameOutOfThePicture() throws {
        let token = DrawnToken(center: CGPoint(x: 100, y: 600), rimName: "VORZA")
        let pawn = try #require(try extractTokens([[token]], background: true).pawns.first)
        guard case .token(let pictures) = pawn.shape, let picture = image(fromPNG: pictures.front)
        else { Issue.record("no token picture"); return }
        let middle = picture.width / 2
        // Above the art's opaque half the art is transparent: the dark page must not show through.
        #expect(pixel(of: picture, x: middle, y: picture.height / 4)[3] == 0)
        #expect(pixel(of: picture, x: 2, y: 2)[3] == 0)
        #expect(pixel(of: picture, x: middle, y: picture.height * 3 / 4)[3] == 255)
        // The name along the rim is left out too: the letters' row shows only art.
        let rim = pixel(of: picture, x: middle, y: picture.height - picture.height / 9)
        #expect(rim[3] == 0 || rim[0] > 100 || rim[1] > 100)
    }

    @Test func pairsOnlyTokensMirroredWithTheirBacks() throws {
        let page = PageScanner.scan(document(tokenPDF(pages: [[DrawnToken(center: CGPoint(x: 100, y: 600))]]))
                                        .page(at: 1)!)
        let fronts = TokenFinder.tokens(on: page)
        #expect(fronts.count == 1)
        #expect(TokenPairing.backs(for: fronts, among: []) == nil)
        #expect(TokenPairing.backs(for: [], among: fronts) == nil)
        // Other art where the back would be, with no label, is the front of another token.
        let other = PageScanner.scan(document(tokenPDF(pages: [[
            DrawnToken(center: CGPoint(x: letterPage.width - 100, y: 600), art: artImage(variant: 1))
        ]])).page(at: 1)!)
        #expect(TokenPairing.backs(for: fronts, among: TokenFinder.tokens(on: other)) == nil)
    }

    @Test func joinsLettersSetOneByOneIntoALine() {
        let glyphs = ["3", "AEON GUARD,", "S", "P", "Y", " ", "1", "© 2026 PAIZO INC."].map {
            TextGlyph(text: $0, origin: .zero)
        }
        #expect(FoundToken.lines(of: glyphs) == ["3", "AEON GUARD,", "SPY 1", "© 2026 PAIZO INC."])
    }

    @Test func sizesTokensByTheirBase() {
        #expect(PawnSize.token(diameter: 54) == .medium)
        #expect(PawnSize.token(diameter: 72) == .medium)
        #expect(PawnSize.token(diameter: 144) == .large)
        #expect(PawnSize.token(diameter: 214) == .huge)
        #expect(PawnSize.token(diameter: 288) == .gargantuan)
    }
}
