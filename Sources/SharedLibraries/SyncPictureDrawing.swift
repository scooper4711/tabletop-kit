import ArtExtraction
import Foundation

/// Drawing the pictures art lacks, so they can be uploaded (R4.8). Art moved in from an app's old library has no
/// saved picture until something shows it, and Pawn Shop draws pawns straight from the PDF.
extension SharedLibrary {
    /// Draws up to `limit` pictures for art without one that has a print in a PDF this app can reach. Art with no
    /// picture takes that of the first such print in its order, figures first. Art that names a picture whose file
    /// is gone gets it back only from the print that picture was drawn from; any other picture comes from iCloud.
    /// Returns how many it drew; 0 means none are left that this app can draw.
    public func drawMissingPictures(limit: Int) throws -> Int {
        guard limit > 0 else { return 0 }
        let reachable = Set(try sources().filter { status(of: $0) == .available }.map(\.id))
        guard !reachable.isEmpty else { return 0 }
        var remaining = try idsOfArtWithoutPicture()[...]
        while !remaining.isEmpty {
            var jobs: [String: [PictureJob]] = [:]
            var queued = 0
            while queued < limit, !remaining.isEmpty {
                let chunk = remaining.prefix(limit - queued)
                remaining = remaining.dropFirst(chunk.count)
                for job in try pictureJobs(forArt: Array(chunk), reachable: reachable) {
                    jobs[job.print.print.sourceID, default: []].append(job)
                    queued += 1
                }
            }
            let drawn = try draw(jobs)
            if drawn > 0 { return drawn }
        }
        return 0
    }

    // MARK: Helpers

    private func idsOfArtWithoutPicture() throws -> [String] {
        try connection().rows("SELECT id, picture FROM art ORDER BY id").compactMap { row in
            guard let id = row.text("id") else { return nil }
            return row.text("picture").map { hasPicture($0) } == true ? nil : id
        }
    }

    private func pictureJobs(forArt ids: [String], reachable: Set<String>) throws -> [PictureJob] {
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        let entries = try ArtRows.entries(in: try connection(), where: "id IN (\(placeholders))",
                                          ids.map { .text($0) })
        return entries.sorted { $0.id.uuidString < $1.id.uuidString }.compactMap { entry in
            let prints = entry.prints.filter { reachable.contains($0.print.sourceID) }
            guard let named = entry.picture else { return prints.first.map { PictureJob(print: $0) } }
            return prints.first { Self.pictureName(drawnFrom: $0) == named }
                .map { PictureJob(print: $0, isRedraw: true) }
        }
    }

    private func draw(_ jobs: [String: [PictureJob]]) throws -> Int {
        let sources = try self.sources()
        var drawn = 0
        for (sourceID, sourceJobs) in jobs {
            guard let source = sources.first(where: { $0.id == sourceID }) else { continue }
            drawn += try withFile(of: source) { url in try drawPictures(sourceJobs, from: url) } ?? 0
        }
        return drawn
    }
}
