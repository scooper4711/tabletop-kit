@testable import ArtExtraction
import Foundation
import Testing

struct FileReferenceTests {
    @Test func asksForSecurityScopeOnlyInTheSandbox() {
        #expect(FileReference.usesSecurityScope(environment: ["APP_SANDBOX_CONTAINER_ID": "com.example.app"]))
        #expect(!FileReference.usesSecurityScope(environment: [:]))
    }

    @Test func remembersAFileWithoutTheSandbox() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("file-reference-\(UUID()).txt")
        try Data("pawn".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let reference = try FileReference(file)

        #expect(reference.withAccess { try? String(contentsOf: $0, encoding: .utf8) } == "pawn")
    }
}
