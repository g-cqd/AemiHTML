internal import AemiKernel
internal import AemiKernels

extension HTMLTokenizer {
    struct Decoded {
        var first: UInt32
        var second: UInt32?
    }

    /// In text: a reference at `pos` (a `&`) is decoded and emitted. False if there is none, and `pos` stays.
    mutating func characterReference(inAttribute: Bool) -> Bool {
        guard let decoded = decodeReference(inAttribute: inAttribute) else { return false }
        emitScalars(decoded.first, decoded.second)
        return true
    }

    /// 13.2.5.72 to 13.2.5.80: the reference at `pos` (a `&`), if there is one, and `pos` after it; else nil, and `pos` stays (the `&` is then text, and what follows is read as it comes).
    mutating func decodeReference(inAttribute: Bool) -> Decoded? {
        let next = byte(pos + 1)
        if next == 0x23 { return decodeNumeric() }
        guard Self.isAlphanumeric(next) else { return nil }
        return decodeNamed(inAttribute: inAttribute)
    }

    /// The longest key that is a prefix of what follows the `&`: a name with its `;`, else a legacy name without one (13.2.5.73).
    private mutating func decodeNamed(inAttribute: Bool) -> Decoded? {
        let start = pos + 1
        var end = start
        while end < count, end - start < EntityTable.longestName, Self.isAlphanumeric(Int(input[end])) { end += 1 }
        let run = end - start
        let semicolon = byte(end) == 0x3B
        var matched = -1
        var found: EntityTable.Entity?
        if semicolon, run + 1 <= EntityTable.longestName,
            let entity = EntityTable.lookup(in: input, start: start, length: run + 1)
        {
            matched = run + 1
            found = entity
        } else {
            var length = run
            while length >= 2 {
                if let entity = EntityTable.lookup(in: input, start: start, length: length) {
                    matched = length
                    found = entity
                    break
                }
                length -= 1
            }
        }
        guard let entity = found else {
            // The whole run of letters and digits, however long, and a `;` after it: an unknown name (13.2.5.79).
            var whole = end
            while Self.isAlphanumeric(byte(whole)) { whole += 1 }
            if byte(whole) == 0x3B { error(.unknownNamedCharacterReference) }
            return nil
        }
        let after = start + matched
        let endsWithSemicolon = input[after - 1] == 0x3B
        if !endsWithSemicolon {
            let following = byte(after)
            // For historical reasons a reference in an attribute that is not closed and is followed by `=` or a letter or digit is left as it is.
            if inAttribute, following == 0x3D || Self.isAlphanumeric(following) { return nil }
            pos = after
            error(.missingSemicolonAfterCharacterReference)
        } else {
            pos = after
        }
        return Decoded(first: entity.first, second: entity.second)
    }

    private static let windows1252: [UInt32] = [
        0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D,
        0x017D,
        0x8F, 0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153,
        0x9D,
        0x017E, 0x0178
    ]

    /// 13.2.5.75 to 13.2.5.80: `&#` and decimal digits, or `&#x` and hex digits, then an optional `;`.
    private mutating func decodeNumeric() -> Decoded? {
        var index = pos + 2
        let hex = byte(index) == 0x78 || byte(index) == 0x58
        if hex { index += 1 }
        let digitsStart = index
        var value: UInt32 = 0
        while true {
            let digit = byte(index)
            var number: UInt32
            if digit >= 0x30, digit <= 0x39 {
                number = UInt32(digit - 0x30)
            } else if hex, digit >= 0x61, digit <= 0x66 {
                number = UInt32(digit - 0x61 + 10)
            } else if hex, digit >= 0x41, digit <= 0x46 {
                number = UInt32(digit - 0x41 + 10)
            } else {
                break
            }
            if hex {
                number = Swift.min(value, 0x110000) << 4 | number
            } else {
                number = Swift.min(value, 0x110000) * 10 + number
            }
            value = Swift.min(number, 0x110000)
            index += 1
        }
        guard index > digitsStart else {
            error(.absenceOfDigitsInNumericCharacterReference)
            return nil
        }
        if byte(index) == 0x3B {
            index += 1
        } else {
            pos = index
            error(.missingSemicolonAfterCharacterReference)
        }
        pos = index
        return Decoded(first: numericScalar(value))
    }

    /// 13.2.5.80: what a numeric reference stands for.
    private mutating func numericScalar(_ code: UInt32) -> UInt32 {
        switch code {
            case 0:
                error(.nullCharacterReference)
                return 0xFFFD
            case 0x110000...:
                error(.characterReferenceOutsideUnicodeRange)
                return 0xFFFD
            case 0xD800 ... 0xDFFF:
                error(.surrogateCharacterReference)
                return 0xFFFD
            case 0xFDD0 ... 0xFDEF:
                error(.noncharacterCharacterReference)
                return code
            case _ where code & 0xFFFE == 0xFFFE:
                error(.noncharacterCharacterReference)
                return code
            case 0x80 ... 0x9F:
                error(.controlCharacterReference)
                return Self.windows1252[Int(code - 0x80)]
            case 0x0D, 0x01 ... 0x08, 0x0B, 0x0E ... 0x1F, 0x7F:
                error(.controlCharacterReference)
                return code
            default: return code
        }
    }
}
