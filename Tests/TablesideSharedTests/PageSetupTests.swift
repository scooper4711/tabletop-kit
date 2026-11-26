#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import TablesideShared

/// A page setup that differs from the system's default in paper and orientation.
@MainActor
private func makeLandscapeA3() -> NSPrintInfo {
    let setup = NSPrintInfo()
    setup.paperSize = CGSize(width: 841.89, height: 1190.55)
    setup.orientation = .landscape
    return setup
}

@MainActor @Suite struct PageSetupArchiveTests {
    @Test func aPageSetupComesBackFromItsData() throws {
        let chosen = makeLandscapeA3()
        let data = try #require(PageSetupArchive.data(from: chosen))

        let restored = try #require(PageSetupArchive.setup(from: data))
        #expect(restored.paperSize == chosen.paperSize)
        #expect(restored.orientation == .landscape)
        #expect(restored.imageablePageBounds == chosen.imageablePageBounds)
        #expect(restored.printer.name == chosen.printer.name)
    }

    @Test func dataThatIsNotAPageSetupGivesNone() {
        #expect(PageSetupArchive.setup(from: Data("not a page setup".utf8)) == nil)
    }
}

@MainActor @Suite struct PageSetupStoreTests {
    private let suiteName = "PageSetupStoreTests.\(UUID().uuidString)"

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    @Test func nothingIsSavedUntilAPageSetupIsChosen() throws {
        #expect(PageSetupStore(defaults: try makeDefaults()).savedSetup == nil)
    }

    @Test func theChosenPageSetupIsKeptAcrossLaunches() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        PageSetupStore(defaults: defaults).save(makeLandscapeA3())

        let restored = try #require(PageSetupStore(defaults: defaults).savedSetup)
        #expect(restored.paperSize == makeLandscapeA3().paperSize)
        #expect(restored.orientation == .landscape)
    }

    @Test func aLaterChoiceReplacesTheSavedOne() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PageSetupStore(defaults: defaults)
        store.save(makeLandscapeA3())
        let portrait = makeLandscapeA3()
        portrait.orientation = .portrait
        store.save(portrait)

        #expect(store.savedSetup?.orientation == .portrait)
    }

    @Test func eachKeyKeepsItsOwnSetup() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        PageSetupStore(defaults: defaults, key: "sheetPageSetup").save(makeLandscapeA3())

        #expect(PageSetupStore(defaults: defaults).savedSetup == nil)
        #expect(PageSetupStore(defaults: defaults, key: "sheetPageSetup").savedSetup != nil)
    }

    @Test func aSavedSetupThatCannotBeReadIsIgnored() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not a page setup".utf8), forKey: PageSetupStore.defaultKey)

        #expect(PageSetupStore(defaults: defaults).savedSetup == nil)
    }
}
#endif
