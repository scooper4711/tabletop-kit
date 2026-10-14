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

    @Test func licensesAreTheFoldersTextFilesTitledByName() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "ORC text".write(to: folder.appendingPathComponent("ORC License.md"), atomically: true, encoding: .utf8)
        try "OGL text".write(to: folder.appendingPathComponent("Open Game License.txt"), atomically: true,
                             encoding: .utf8)
        try "not a license".write(to: folder.appendingPathComponent("logo.png"), atomically: true, encoding: .utf8)
        let licensed = info.licensed(by: folder)
        #expect(licensed.licenses.map(\.title) == ["Open Game License", "ORC License"])
        #expect(licensed.panelText.hasSuffix("OPEN GAME LICENSE\n\nOGL text\n\nORC LICENSE\n\nORC text"))
        #expect(LicenseText.all(in: folder.appendingPathComponent("missing")).isEmpty)
    }

    @MainActor
    @Test func licensePageRenders() {
        let page = LicensePage(license: LicenseText(title: "MIT", text: "Permission is hereby granted…"))
        #expect(ImageRenderer(content: page.frame(width: 400, height: 300)).cgImage != nil)
    }

    @Test(arguments: [info, AboutInfo(appName: "Bare", tagline: "", credits: [], contactURL: AboutInfo.paizoURL),
                      AboutInfo(appName: "Licensed", tagline: "", credits: [], contactURL: AboutInfo.paizoURL,
                                licenses: [LicenseText(title: "MIT", text: "Permission")])])
    @MainActor
    func aboutSheetRenders(info: AboutInfo) {
        let sheet = AboutSheet(info: info).frame(width: 500, height: 700)
        #expect(ImageRenderer(content: sheet).cgImage != nil)
    }
}
