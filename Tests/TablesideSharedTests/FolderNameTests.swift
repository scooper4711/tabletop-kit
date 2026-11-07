import Foundation
@testable import TablesideShared
import Testing

@Suite struct FolderNameTests {
    let home = "/Users/gm"

    @Test func namesAnAppsDocumentsFolderOnTheIPadAsScrollkeepers() {
        let path = "/private/var/mobile/Containers/Data/Application/23170C81-51B2-4D19-B33D-244B7189E456/Documents"
        #expect(FolderName(path: path, homeDirectory: home)
                == FolderName(title: "Scrollkeeper", location: "On My iPad"))
        #expect(FolderName(path: path + "/Pathfinder/Bestiary", homeDirectory: home).title
                == "Scrollkeeper ▸ Pathfinder ▸ Bestiary")
    }

    @Test func namesScrollkeepersDownloadFolderOnTheMac() {
        let path = home + "/Library/Application Support/Scrollkeeper/Files"
        #expect(FolderName(path: path, homeDirectory: home)
                == FolderName(title: "Scrollkeeper", location: "On this Mac"))
        #expect(FolderName(path: path + "/Pawns/", homeDirectory: home).title == "Scrollkeeper ▸ Pawns")
    }

    @Test func namesTheDownloadFolderTheToolkitShares() {
        let path = home + "/Library/Group Containers/9SWRBY8HN9.io.github.scooper4711.tableside/Scrollkeeper/Files"
        #expect(FolderName(path: path, homeDirectory: home)
                == FolderName(title: "Scrollkeeper", location: "On this Mac"))
        #expect(FolderName(url: URL(filePath: path + "/Murder in Metal City", directoryHint: .isDirectory),
                           homeDirectory: home).title == "Scrollkeeper ▸ Murder in Metal City")
        #expect(FolderName.place(ofFile: path + "/Murder in Metal City/Tokens.pdf", homeDirectory: home)
                == "Scrollkeeper ▸ Murder in Metal City · On this Mac")
    }

    @Test func namesScrollkeepersOwnFolderOutsideTheAppGroup() {
        let path = home + "/Library/Containers/5C8C761D/Data/Library/Application Support/Scrollkeeper/Files"
        #expect(FolderName(path: path, homeDirectory: home)
                == FolderName(title: "Scrollkeeper", location: "On this Mac"))
    }

    @Test func namesOtherFoldersByNameAndPlace() {
        #expect(FolderName(path: home + "/Documents/Paizo", homeDirectory: home)
                == FolderName(title: "Paizo", location: "~/Documents"))
        #expect(FolderName(path: home + "/Paizo", homeDirectory: home + "/")
                == FolderName(title: "Paizo", location: "~"))
        #expect(FolderName(path: "/Volumes/Games/Paizo", homeDirectory: home)
                == FolderName(title: "Paizo", location: "/Volumes/Games"))
        #expect(FolderName(path: "/Users/gmx/Paizo", homeDirectory: home).location == "/Users/gmx")
    }

    @Test func leavesAnIncompleteContainerPathAlone() {
        #expect(FolderName(path: "/private/var/mobile/Containers/Data/Application", homeDirectory: home)
                == FolderName(title: "Application", location: "/private/var/mobile/Containers/Data"))
        #expect(FolderName(path: "/Documents", homeDirectory: home) == FolderName(title: "Documents", location: "/"))
    }

    @Test func placesAPDFByItsFolder() {
        let documents = "/private/var/mobile/Containers/Data/Application/23170C81-51B2-4D19-B33D-244B7189E456/Documents"
        #expect(FolderName.place(ofFile: documents + "/Pathfinder/Pawns.pdf", homeDirectory: home)
                == "Scrollkeeper ▸ Pathfinder · On My iPad")
        #expect(FolderName.place(ofFile: documents + "/Pawns.pdf", homeDirectory: home)
                == "Scrollkeeper · On My iPad")
        #expect(FolderName.place(ofFile: home + "/Downloads/Pawns.pdf", homeDirectory: home) == "Downloads · ~")
    }

    @Test func leavesAPlaceThatIsNotAPathAlone() {
        #expect(FolderName.place(ofFile: "Kept in the app", homeDirectory: home) == "Kept in the app")
    }
}
