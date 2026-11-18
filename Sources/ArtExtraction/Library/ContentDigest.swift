import CryptoKit
import Foundation

/// SHA-256 as lowercase hexadecimal: how the libraries tell a file's, an image's or a record's content apart.
public enum ContentDigest {
    public static func hex(of data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    public static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
