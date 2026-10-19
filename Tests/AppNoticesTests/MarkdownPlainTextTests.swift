@testable import AppNotices
import Foundation
import Testing

struct MarkdownPlainTextTests {
    @Test func aTableBecomesOneLinePerRow() {
        let markdown = """
            | Condition | Icon | Author |
            |---|:---:|---|
            | blinded | [sight-disabled](https://game-icons.net/sight-disabled.html) | Skoll |
            """
        #expect(MarkdownPlainText.convert(markdown) == """
            Condition · Icon · Author
            blinded · sight-disabled (https://game-icons.net/sight-disabled.html) · Skoll
            """)
    }

    @Test func headingsLinksEmphasisAndCodeLoseTheirMarkup() {
        let markdown = "# Condition icons\n\nFrom [game-icons.net](https://game-icons.net), **unaltered**; "
            + "`make bestiary` renders them."
        #expect(MarkdownPlainText.convert(markdown) == """
            Condition icons

            From game-icons.net (https://game-icons.net), unaltered; make bestiary renders them.
            """)
    }

    @Test func wrappedParagraphLinesAreJoined() {
        let first = String(repeating: "word ", count: 15) + "and"
        #expect(MarkdownPlainText.convert("\(first)\nthe rest.\n\nNext paragraph.")
            == "\(first) the rest.\n\nNext paragraph.")
    }

    @Test func shortLinesAndNewItemsStayOnTheirOwnLines() {
        let long = String(repeating: "x", count: 80)
        let markdown = "OPEN GAME LICENSE Version 1.0a\nThe following text\n\(long)\n1. Definitions\n"
            + "* Core Books\n\t*  Player Core © 2023"
        #expect(MarkdownPlainText.convert(markdown) == """
            OPEN GAME LICENSE Version 1.0a
            The following text
            \(long)
            1. Definitions
            • Core Books
            \t• Player Core © 2023
            """)
    }
}
