import CloudKit
import Foundation
import SharedLibraries
import Testing
@testable import TablesideSync

/// The library's records as CloudKit records (library sync design, "Records in CloudKit").
@Suite struct LibraryRecordCoderTests {
    let device = TestDevice()

    var coder: LibraryRecordCoder { LibraryRecordCoder(outgoingFolder: device.root.appending(path: "Outgoing")) }

    /// What the library has to send, by kind.
    func outgoingRecords() throws -> [SyncKind: OutgoingRecord] {
        let library = try device.library()
        try device.fillWithEveryKind(library)
        var records: [SyncKind: OutgoingRecord] = [:]
        for id in try library.syncCandidates().saves {
            records[id.kind] = try library.outgoingRecord(id)
        }
        return records
    }

    @Test func carriesEveryKindThereAndBack() throws {
        let records = try outgoingRecords()
        #expect(Set(records.keys) == Set(SyncKind.allCases))
        for (kind, outgoing) in records {
            let record = try coder.record(for: outgoing)
            #expect(record.recordType == LibraryRecordCoder.recordType(of: kind))
            #expect(record["format"] as? Int64 == 1 && record["title"] as? String == outgoing.record.title)
            let back = try #require(savedRecord(LibraryRecordCoder.remoteChange(from: record)))
            #expect(back.id == outgoing.record.id && back.payload == outgoing.record.payload)
            #expect(back.title == outgoing.record.title)
            #expect(back.file?.lastPathComponent == outgoing.record.file?.lastPathComponent)
        }
    }

    @Test func sendsAReadingAsAnAssetAndRemovesItsFileOnceSent() throws {
        let outgoing = try #require(try outgoingRecords()[.source])
        let record = try coder.record(for: outgoing)
        let file = try #require((record["payload"] as? CKAsset)?.fileURL)
        #expect(try Data(contentsOf: file) == outgoing.record.payload)

        coder.removeOutgoingFile(of: record.recordID)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        _ = try coder.record(for: outgoing)
        coder.removeOutgoingFiles()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func sendsCustomArtWithItsImageAndTheRestAsBytes() throws {
        let records = try outgoingRecords()
        let customArt = try coder.record(for: try #require(records[.customArt]))
        #expect(try Data(contentsOf: try #require((customArt["image"] as? CKAsset)?.fileURL)) == Data([1, 2, 3]))
        let note = try coder.record(for: try #require(records[.note]))
        #expect(note["payload"] is Data && note["image"] == nil)
    }

    @Test func buildsARecordOverTheServersKnownCopy() throws {
        var outgoing = try #require(try outgoingRecords()[.note])
        let known = CKRecord(recordType: "Note", recordID: .library("note-known"))
        outgoing.systemFields = LibraryRecordCoder.systemFields(of: known)
        #expect(try coder.record(for: outgoing).recordID == known.recordID)

        outgoing.systemFields = Data([1, 2])
        #expect(try coder.record(for: outgoing).recordID == .library(outgoing.record.id.name))
    }

    @Test func readsNothingFromARecordThatIsNotTheLibrarys() throws {
        let elsewhere = CKRecord.ID(recordName: "note-1", zoneID: LibraryRecordCoder.picturesZone)
        #expect(LibraryRecordCoder.remoteChange(from: CKRecord(recordType: "Note", recordID: elsewhere)) == nil)
        let picture = CKRecord(recordType: "Picture", recordID: .library("note-1"))
        #expect(LibraryRecordCoder.remoteChange(from: picture) == nil)
        let unnamed = CKRecord(recordType: "Note", recordID: .library("campaign-1"))
        #expect(LibraryRecordCoder.remoteChange(from: unnamed) == nil)
    }

    @Test func handsOnARecordItCannotReadWithAnEmptyPayload() throws {
        let record = CKRecord(recordType: "Source", recordID: .library("source-abc"))
        record["format"] = Int64(2)
        record["payload"] = Data("a later layout".utf8)
        let content = try #require(savedRecord(LibraryRecordCoder.remoteChange(from: record)))
        #expect(content.payload.isEmpty && content.title.isEmpty)
        let change = try #require(LibraryRecordCoder.remoteChange(from: record))
        #expect(try device.library().applyRemote([change]).parked == 1)
    }

    @Test func failsWhenAReadingCannotBeWritten() throws {
        let outgoing = try #require(try outgoingRecords()[.source])
        let blocked = device.root.appending(path: "file")
        try Data().write(to: blocked)
        let coder = LibraryRecordCoder(outgoingFolder: blocked.appending(path: "Outgoing"))
        #expect(throws: SharedLibraryError.self) { try coder.record(for: outgoing) }
    }
}
