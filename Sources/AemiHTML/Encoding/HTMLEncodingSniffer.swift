/// How sure the encoding of a document is (13.2.3): "certain" when a byte order mark or the transport layer said so, "tentative" when a `meta` or a guess did.
public enum HTMLEncodingConfidence: Sendable { case certain, tentative }

/// The encoding sniffing algorithm of the HTML Standard (13.2.3.1): a byte order mark, then the transport layer's charset, then a prescan of the first 1024 bytes for a `meta` that declares one, then a fallback.
///
/// The standard's last step is a default that depends on the reader's locale; here it is a choice made from the bytes: UTF-8 if they are well-formed UTF-8 (which text in another encoding almost never is), windows-1252 if not.
public enum HTMLEncodingSniffer {
    /// What was found, and how many bytes of byte order mark come off the front.
    public struct Result: Sendable, Equatable {
        public var encoding: HTMLEncoding
        public var confidence: HTMLEncodingConfidence
        public var byteOrderMarkLength: Int
    }

    /// The encoding of `bytes`, how sure it is, and how long a byte order mark is.
    /// - Parameters:
    ///   - bytes: the document, or its first kilobyte at least.
    ///   - transportLabel: the charset the transport layer gave (the `charset` of a `Content-Type`), if any; a label the standard does not know is ignored.
    ///   - fallbackIsUTF8: whether to try UTF-8 before windows-1252 when nothing declares an encoding; with `false` the fallback is always windows-1252.
    /// - Returns: the encoding, its confidence, and the length of the byte order mark to skip.
    public static func sniff(_ bytes: [UInt8], transportLabel: String? = nil, fallbackIsUTF8: Bool = true) -> Result {
        if let (encoding, length) = byteOrderMark(bytes) {
            return Result(encoding: encoding, confidence: .certain, byteOrderMarkLength: length)
        }
        if let label = transportLabel, let encoding = HTMLEncoding(label: label), encoding != .replacement {
            return Result(encoding: encoding, confidence: .certain, byteOrderMarkLength: 0)
        }
        if let encoding = prescan(bytes) {
            return Result(encoding: encoding, confidence: .tentative, byteOrderMarkLength: 0)
        }
        let guess: HTMLEncoding = fallbackIsUTF8 && HTMLEncodingSniffer.isWellFormedUTF8(bytes) ? .utf8 : .windows1252
        return Result(encoding: guess, confidence: .tentative, byteOrderMarkLength: 0)
    }

    /// BOM sniffing (the Encoding Standard): UTF-8, UTF-16BE or UTF-16LE by the first two or three bytes.
    public static func byteOrderMark(_ bytes: [UInt8]) -> (HTMLEncoding, Int)? {
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { return (.utf8, 3) }
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF { return (.utf16BE, 2) }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE { return (.utf16LE, 2) }
        return nil
    }

    /// Whether the bytes are UTF-8 from end to end.
    static func isWellFormedUTF8(_ bytes: [UInt8]) -> Bool { HTMLTokenizer.isWellFormedUTF8(bytes) }
}
