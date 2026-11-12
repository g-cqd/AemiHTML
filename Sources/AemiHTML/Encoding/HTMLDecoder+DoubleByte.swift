extension HTMLDecoder {
    /// The loop of a double-byte encoding (Big5 12.1, EUC-KR 13.1, Shift_JIS 14.2). `single` reads a byte with no lead before it:
    /// the scalar it stands for (U+FFFD for an error), or nil for a lead. `pair` writes what a lead and its trail stand for and says
    /// whether they stood for anything; when not, U+FFFD is written and an ASCII trail is read again. A lead at the end is U+FFFD.
    @inline(__always)
    static func decodeDoubleByte(
        _ bytes: ArraySlice<UInt8>,
        single: (UInt8) -> UInt32?,
        pair: (Int, UInt8, inout [UInt8]) -> Bool
    ) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count * 2)
        var lead: UInt8 = 0
        var position = bytes.startIndex
        while position < bytes.endIndex {
            let byte = bytes[position]
            position += 1
            if lead != 0 {
                let first = Int(lead)
                lead = 0
                guard !pair(first, byte, &out) else { continue }
                if byte < 0x80 { position -= 1 }
                put(0xFFFD, &out)
            } else if let scalar = single(byte) {
                put(scalar, &out)
            } else {
                lead = byte
            }
        }
        if lead != 0 { put(0xFFFD, &out) }
        return out
    }
}
