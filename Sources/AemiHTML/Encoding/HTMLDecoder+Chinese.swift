extension HTMLDecoder {
    /// gb18030, and GBK, which decodes as it does (Encoding Standard 11.1): one byte, two bytes into the index, or four bytes into the ranges.
    static func decodeGB18030(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        var machine = GB18030()
        machine.out.reserveCapacity(bytes.count * 2)
        var position = bytes.startIndex
        while position < bytes.endIndex {
            let byte = bytes[position]
            position += 1
            position -= machine.step(byte)
        }
        if machine.isMidSequence { put(0xFFFD, &machine.out) }
        return machine.out
    }

    /// "The index gb18030 ranges code point" for a four-byte pointer.
    static func codePoint(forRangePointer pointer: Int) -> UInt32? {
        if (pointer > 39419 && pointer < 189000) || pointer > 1_237_575 { return nil }
        if pointer == 7457 { return 0xE7C7 }
        let ranges = EncodingIndexes.gb18030Ranges
        // The last range that starts at or before the pointer (the table is ascending).
        var low = 0
        var high = ranges.count - 1
        var found = -1
        while low <= high {
            let middle = (low + high) / 2
            if Int(ranges[middle].pointer) <= pointer {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        guard found >= 0 else { return nil }
        // @dl:accept -- the end of one decoder and the start of the next, each the Encoding Standard's
        return ranges[found].codePoint + UInt32(pointer) - ranges[found].pointer
    }

    /// Big5 (12.1): the index, with four pointers that stand for a letter and a combining mark.
    // @dl:accept -- each encoding reads its pairs by the Encoding Standard's own rule; the opening steps match, the ranges and indexes differ
    static func decodeBig5(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        let index = EncodingIndexes.big5
        return decodeDoubleByte(bytes, single: asciiOrLead) { first, byte, out in
            guard (0x40 ... 0x7E).contains(byte) || (0xA1 ... 0xFE).contains(byte) else { return false }
            let pointer = (first - 0x81) * 157 + Int(byte) - (byte < 0x7F ? 0x40 : 0x62)
            switch pointer {
                case 1133, 1135, 1164, 1166:
                    put(pointer < 1164 ? 0xCA : 0xEA, &out)
                    put(pointer == 1133 || pointer == 1164 ? 0x304 : 0x30C, &out)
                default:
                    guard pointer < index.count, index[pointer] != none else { return false }
                    put(index[pointer], &out)
            }
            return true
        }
    }

    /// A Big5 or EUC-KR byte with no lead before it: ASCII as itself, nil for a lead (0x81 ... 0xFE), else U+FFFD.
    private static func asciiOrLead(_ byte: UInt8) -> UInt32? {
        byte < 0x80 ? UInt32(byte) : (0x81 ... 0xFE).contains(byte) ? nil : 0xFFFD
    }

    /// EUC-KR (13.1): the index by two bytes.
    static func decodeEUCKR(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        let index = EncodingIndexes.eucKR
        return decodeDoubleByte(bytes, single: asciiOrLead) { first, byte, out in
            guard byte >= 0x41, byte <= 0xFE else { return false }
            let pointer = (first - 0x81) * 190 + Int(byte) - 0x41
            guard pointer < index.count, index[pointer] != none else { return false }
            put(index[pointer], &out)
            return true
        }
    }
}

/// The decoder state of gb18030: the bytes of a sequence read so far.
private struct GB18030 {
    static let index = EncodingIndexes.gb18030
    var first = 0
    var second = 0
    var third = 0
    var out: [UInt8] = []

    var isMidSequence: Bool { first != 0 || second != 0 || third != 0 }

    private mutating func emit(_ value: UInt32) { HTMLDecoder.put(value, &out) }

    private mutating func reset() {
        first = 0
        second = 0
        third = 0
    }

    /// One byte; returns how many of the bytes just read are to be read again.
    mutating func step(_ byte: UInt8) -> Int {
        if third != 0 { return fourthByte(byte) }
        if second != 0 {
            if byte >= 0x81, byte <= 0xFE {
                third = Int(byte)
                return 0
            }
            reset()
            emit(0xFFFD)
            return 2
        }
        if first != 0 { return secondByte(byte) }
        if byte < 0x80 {
            emit(UInt32(byte))
        } else if byte == 0x80 {
            emit(0x20AC)
        } else if byte >= 0x81, byte <= 0xFE {
            first = Int(byte)
        } else {
            emit(0xFFFD)
        }
        return 0
    }

    private mutating func fourthByte(_ byte: UInt8) -> Int {
        guard byte >= 0x30, byte <= 0x39 else {
            // Not a four-byte sequence: the last three bytes are read again.
            reset()
            emit(0xFFFD)
            return 3
        }
        let pointer =
            (first - 0x81) * (10 * 126 * 10) + (second - 0x30) * (10 * 126) + (third - 0x81) * 10 + Int(byte) - 0x30
        reset()
        if let value = HTMLDecoder.codePoint(forRangePointer: pointer) { emit(value) } else { emit(0xFFFD) }
        return 0
    }

    private mutating func secondByte(_ byte: UInt8) -> Int {
        if byte >= 0x30, byte <= 0x39 {
            second = Int(byte)
            return 0
        }
        let lead = first
        first = 0
        if (0x40 ... 0x7E).contains(byte) || (0x80 ... 0xFE).contains(byte) {
            let pointer = (lead - 0x81) * 190 + Int(byte) - (byte < 0x7F ? 0x40 : 0x41)
            if pointer < Self.index.count, Self.index[pointer] != HTMLDecoder.none {
                emit(Self.index[pointer])
                return 0
            }
        }
        emit(0xFFFD)
        return byte < 0x80 ? 1 : 0
    }
}
