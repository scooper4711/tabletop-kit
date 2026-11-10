import AppKit
@testable import AppNotices
import SwiftUI
import Testing

/// The buttons' actions aren't pressed here: SwiftUI builds no accessibility elements in a test host, so there is
/// nothing to press without a UI test. What is drawn is checked instead.
@MainActor
struct EmptyWindowViewTests {
    /// The view drawn into a bitmap, as its bytes.
    private func drawing(title: String = "Open a PDF", isDropTargeted: Bool = false) throws -> Data {
        let view = EmptyWindowView(title: title, symbol: "doc", message: "Drop a PDF here.",
                                   isDropTargeted: isDropTargeted, open: {}, openFromScrollkeeper: {})
        let hosted = NSHostingView(rootView: view)
        hosted.frame = CGRect(x: 0, y: 0, width: 480, height: 360)
        hosted.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosted.bitmapImageRepForCachingDisplay(in: hosted.bounds))
        hosted.cacheDisplay(in: hosted.bounds, to: bitmap)
        return try #require(bitmap.tiffRepresentation)
    }

    @Test func drawsTheSameWindowEachTime() throws {
        #expect(try drawing() == drawing())
    }

    @Test func drawsTheTitleItIsGiven() throws {
        #expect(try drawing(title: "Open a Map") != drawing())
    }

    @Test func outlinesTheWindowOnlyWhileAFileIsDraggedOver() throws {
        #expect(try drawing(isDropTargeted: true) != drawing())
    }
}
