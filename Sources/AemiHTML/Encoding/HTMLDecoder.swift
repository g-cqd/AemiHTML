/// Decoders from the legacy and Unicode encodings of the Encoding Standard to UTF-8, the encoding the parser reads. Each follows the standard's decoder: what it cannot decode becomes U+FFFD as the standard says (one for each ill-formed
/// sequence, with the byte that broke it read again as the start of whatever comes next).
public enum HTMLDecoder {
    /// `bytes` as the Encoding Standard's "decode" reads them: a byte order mark, if there is one, decides the encoding and is dropped; otherwise `encoding` does.
    public static func decode(_ bytes: [UInt8], as encoding: HTMLEncoding) -> [UInt8] {
        if let (marked, length) = HTMLEncodingSniffer.byteOrderMark(bytes) {
            return decode(bytes[length...], as: marked)
        }
        return decode(bytes[...], as: encoding)
    }

    /// The bytes with no byte order mark taken off: the caller has dealt with it.
    static func decode(_ bytes: ArraySlice<UInt8>, as encoding: HTMLEncoding) -> [UInt8] {
        switch encoding {
            case .utf8: Array(String(decoding: bytes, as: UTF8.self).utf8)
            case .utf16LE: decodeUTF16(bytes, bigEndian: false)
            case .utf16BE: decodeUTF16(bytes, bigEndian: true)
            case .xUserDefined: decodeUserDefined(bytes)
            case .replacement: bytes.isEmpty ? [] : replacementCharacter
            case .shiftJIS: decodeShiftJIS(bytes)
            case .eucJP: decodeEUCJP(bytes)
            case .iso2022JP: decodeISO2022JP(bytes)
            case .gbk, .gb18030: decodeGB18030(bytes)
            case .big5: decodeBig5(bytes)
            case .eucKR: decodeEUCKR(bytes)
            default: decodeSingleByte(bytes, encoding)
        }
    }

    static let replacementCharacter: [UInt8] = [0xEF, 0xBF, 0xBD]

    /// Appends the UTF-8 of a scalar (U+FFFD for a value that is not one).
    @inline(__always)
    static func put(_ value: UInt32, _ out: inout [UInt8]) {
        switch value {
            case ..<0x80: out.append(UInt8(value))
            case ..<0x800:
                out.append(0xC0 | UInt8(value >> 6))
                out.append(0x80 | UInt8(value & 0x3F))
            case ..<0x10000:
                if value >= 0xD800 && value <= 0xDFFF {
                    out.append(contentsOf: replacementCharacter)
                } else {
                    out.append(0xE0 | UInt8(value >> 12))
                    out.append(0x80 | UInt8((value >> 6) & 0x3F))
                    out.append(0x80 | UInt8(value & 0x3F))
                }
            case ..<0x110000:
                out.append(0xF0 | UInt8(value >> 18))
                out.append(0x80 | UInt8((value >> 12) & 0x3F))
                out.append(0x80 | UInt8((value >> 6) & 0x3F))
                out.append(0x80 | UInt8(value & 0x3F))
            default: out.append(contentsOf: replacementCharacter)
        }
    }

    /// 0xFFFFF in a packed index: no character at this pointer.
    static let none: UInt32 = 0xFFFFF

    // MARK: Single byte, user-defined, UTF-16

    private static func decodeSingleByte(_ bytes: ArraySlice<UInt8>, _ encoding: HTMLEncoding) -> [UInt8] {
        guard let table = EncodingIndexes.singleByte(encoding) else {
            return Array(String(decoding: bytes, as: UTF8.self).utf8)
        }
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + bytes.count / 2)
        for byte in bytes {
            if byte < 0x80 {
                out.append(byte)
            } else {
                let value = table[Int(byte) - 0x80]
                put(value == 0xFFFF ? 0xFFFD : UInt32(value), &out)
            }
        }
        return out
    }

    /// x-user-defined: ASCII, and the upper half in the private use area (U+F780 ...), which is how a page held binary data in a string.
    private static func decodeUserDefined(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + bytes.count / 2)
        for byte in bytes { put(byte < 0x80 ? UInt32(byte) : 0xF780 + UInt32(byte) - 0x80, &out) }
        return out
    }

    private static func decodeUTF16(_ bytes: ArraySlice<UInt8>, bigEndian: Bool) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + bytes.count / 2)
        var index = bytes.startIndex
        let end = bytes.endIndex
        func unit(at position: Int) -> UInt32 {
            let first = UInt32(bytes[position])
            let second = UInt32(bytes[position + 1])
            return bigEndian ? first << 8 | second : second << 8 | first
        }
        while index + 1 < end {
            let value = unit(at: index)
            index += 2
            if value >= 0xD800 && value <= 0xDBFF {
                // A lead surrogate: it needs a trail one right after it.
                if index + 1 < end {
                    let next = unit(at: index)
                    if next >= 0xDC00 && next <= 0xDFFF {
                        index += 2
                        put(0x10000 + ((value - 0xD800) << 10) + (next - 0xDC00), &out)
                        continue
                    }
                }
                put(0xFFFD, &out)
            } else if value >= 0xDC00 && value <= 0xDFFF {
                put(0xFFFD, &out)
            } else {
                put(value, &out)
            }
        }
        if index < end { put(0xFFFD, &out) }
        return out
    }
}
