extension HTMLEncoding {
    /// The encoding a label names, as the Encoding Standard's "get an encoding" finds it: ASCII white space cut off both ends, ASCII letters in lower case, the label looked up in its table. Nil for a label the standard does not list.
    ///
    /// ```swift
    /// HTMLEncoding(label: " Latin1\n")   // .windows1252, as in every browser
    /// HTMLEncoding(label: "utf-8")       // .utf8
    /// ```
    public init?(label: String) { self.init(label: Array(label.utf8)[...]) }

    /// The same for the bytes of a label (the prescan finds them in a page).
    public init?(label bytes: ArraySlice<UInt8>) {
        var start = bytes.startIndex
        var end = bytes.endIndex
        func isSpace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
        }
        while start < end, isSpace(bytes[start]) { start += 1 }
        while end > start, isSpace(bytes[end - 1]) { end -= 1 }
        // No label is long: a longer one is not one, and a hostile page does not get a `String` out of this.
        guard end > start, end - start <= 32 else { return nil }
        var lowered: [UInt8] = []
        lowered.reserveCapacity(end - start)
        for byte in bytes[start ..< end] { lowered.append(byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte) }
        guard let found = HTMLEncoding.lookup(normalizedLabel: String(decoding: lowered, as: UTF8.self)) else {
            return nil
        }
        self = found
    }
}
