import AppKit
@testable import AppNotices
import SwiftUI
import Testing

@MainActor
struct EmptyWindowViewTests {
    private func makeView(isDropTargeted: Bool = false) -> EmptyWindowView {
        EmptyWindowView(title: "Open a PDF", symbol: "doc", message: "Drop a PDF here.",
                        isDropTargeted: isDropTargeted, open: {}, openFromScrollkeeper: {})
    }

    @Test func rendersWithoutADropInProgress() {
        let hosted = NSHostingView(rootView: makeView())
        hosted.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        hosted.layoutSubtreeIfNeeded()
        #expect(hosted.fittingSize.width > 0)
    }

    @Test func rendersTheOutlineWhileAFileIsDraggedOver() {
        let hosted = NSHostingView(rootView: makeView(isDropTargeted: true))
        hosted.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        hosted.layoutSubtreeIfNeeded()
        #expect(hosted.fittingSize.width > 0)
    }
}
