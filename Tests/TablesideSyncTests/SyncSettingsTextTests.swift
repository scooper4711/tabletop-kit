import Foundation
import SharedLibraries
import Testing
@testable import TablesideSync

/// What an app's sync settings say and offer (R2.5, R4.3, R4.7, R4.9).
@Suite struct SyncSettingsTextTests {
    @Test func saysWhetherTheLibrarySyncsAndWhyNot() {
        let statuses: [SyncStatus] = [.unsupported, .unavailable, .syncing, .upToDate, .paused, .storageFull,
                                      .failed("The disk is full.")]
        let summaries = statuses.map { SyncSettingsText.summary(of: $0, app: .fieldGuide) }
        #expect(Set(summaries).count == statuses.count)
        #expect(summaries[0].contains("This copy of Field Guide") && summaries[1].contains("Sign in to iCloud"))
        #expect(summaries[4].contains("paused") && summaries[5].contains("iCloud is full"))
        #expect(summaries[6].hasSuffix("The disk is full.") && summaries[6].contains("Field Guide next opens"))
    }

    @Test func namesTheOtherAppsThatShareTheSetting() {
        #expect(SyncSettingsText.keepingNote(app: .pawnShop).hasSuffix("Turnkeeper and Field Guide share it."))
        #expect(SyncSettingsText.keepingNote(app: .fieldGuide).hasSuffix("Pawn Shop and Turnkeeper share it."))
    }

    @Test func offersTheWaysToKeepPictures() {
        let choices = PictureKeeping.choices(including: .shown)
        #expect(choices.count == 6 && choices.first == .shown && choices.last == .everything)
        #expect(choices.map(\.title).contains { $0.contains("250") && $0.hasPrefix("Up to") })
        #expect(Set(choices.map(\.title)).count == 6)
        #expect(SyncSettingsText.size(ofBytes: 38_000_000).contains("38"))

        let other = PictureKeeping.upTo(750_000_000)
        #expect(PictureKeeping.choices(including: other)[3] == other)
        #expect(PictureKeeping.choices(including: .upTo(500_000_000)).count == 6)
    }

    @Test func mapsToThePolicyAndBack() {
        for keeping in PictureKeeping.choices(including: .upTo(1)) {
            #expect(PictureKeeping(keeping.policy) == keeping)
        }
        #expect(PictureKeeping(.onDemand(limit: nil)) == .shown && PictureKeeping.everything.policy == .everything)
        #expect(PictureKeeping.upTo(5).policy == .onDemand(limit: 5))
    }
}
