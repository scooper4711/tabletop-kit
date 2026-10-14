import AppKit
@testable import AppNotices
import SwiftUI
import Testing

private let info = AboutInfo(
    appName: "Sample App",
    tagline: "An unofficial sample.",
    credits: ["Art by someone, used under a license.", "Text under the ORC License."],
    contactURL: URL(fileURLWithPath: "/contact")
)

struct AboutInfoTests {
    @Test func communityUseNoticeIsThePolicysWordingWithTheAppsName() {
        #expect(info.communityUseNotice == """
            Sample App uses trademarks and/or copyrights owned by Paizo Inc., used under Paizo's Community Use \
            Policy (paizo.com/licenses/communityuse). We are expressly prohibited from charging you to use or \
            access this content. Sample App is not published, endorsed, or specifically approved by Paizo. For \
            more information about Paizo Inc. and Paizo products, visit paizo.com.
            """)
    }

    @Test func trademarkNoticeIsTheCompatibilityLicensesLine() {
        #expect(AboutInfo.trademarkNotice
            == "Pathfinder and Starfinder are registered trademarks and copyrights of Paizo Inc.")
    }

    @Test func panelTextHasEveryParagraphInOrder() {
        let paragraphs = info.panelText.components(separatedBy: "\n\n")
        #expect(paragraphs == [
            "An unofficial sample.", info.communityUseNotice, AboutInfo.trademarkNotice,
            "Art by someone, used under a license.", "Text under the ORC License.", "Contact: file:///contact"
        ])
    }

    @Test func panelCreditsCarryThePanelText() {
        #expect(AboutPanel.credits(for: info).string == info.panelText)
    }

    @Test(arguments: [info, AboutInfo(appName: "Bare", tagline: "", credits: [], contactURL: AboutInfo.paizoURL)])
    @MainActor
    func aboutSheetRenders(info: AboutInfo) {
        let sheet = AboutSheet(info: info).frame(width: 500, height: 700)
        #expect(ImageRenderer(content: sheet).cgImage != nil)
    }
}
