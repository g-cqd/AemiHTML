extension HTMLEncodingSniffer {
    /// The prescan of the standard (13.2.3.2) over the first 1024 bytes: the encoding a `meta` declares (`<meta charset=…>` or `<meta http-equiv=content-type content="…; charset=…">`), or nil. A declaration of UTF-16 means UTF-8 (a page that can be read
    /// this far as ASCII is not UTF-16), and of x-user-defined means windows-1252.
    public static func prescan(_ bytes: [UInt8]) -> HTMLEncoding? {
        do { return try scan(bytes) } catch { return nil }
    }

    /// Running out of bytes in the middle of a tag is the standard's end condition: the prescan stops and finds nothing.
    private struct Exhausted: Error {}

    private static func scan(_ bytes: [UInt8]) throws -> HTMLEncoding? {
        let end = Swift.min(bytes.count, 1024)
        if end >= 6 {
            if bytes[0] == 0x3C, bytes[1] == 0, bytes[2] == 0x3F, bytes[3] == 0, bytes[4] == 0x78, bytes[5] == 0 {
                return .utf16LE
            }
            if bytes[0] == 0, bytes[1] == 0x3C, bytes[2] == 0, bytes[3] == 0x3F, bytes[4] == 0, bytes[5] == 0x78 {
                return .utf16BE
            }
        }
        var position = 0
        while position < end {
            guard bytes[position] == 0x3C else {
                position += 1
                continue
            }
            let next = position + 1 < end ? bytes[position + 1] : 0
            if next == 0x21, position + 3 < end, bytes[position + 2] == 0x2D, bytes[position + 3] == 0x2D {
                // A comment: on to the `>` of its `-->` (the dashes may be the ones that opened it).
                var scan = position + 4
                while scan < end, !(bytes[scan] == 0x3E && bytes[scan - 1] == 0x2D && bytes[scan - 2] == 0x2D) {
                    scan += 1
                }
                if scan >= end { return nil }
                position = scan + 1
            } else if isMetaStart(bytes, at: position, end: end) {
                position += 5
                switch try scanMeta(bytes, &position, end: end) {
                    case .found(let encoding): return encoding
                    case .keepGoing: break
                }
            } else if isLetter(next) || (next == 0x2F && position + 2 < end && isLetter(bytes[position + 2])) {
                position += next == 0x2F ? 2 : 1
                while position < end, !isSpace(bytes[position]), bytes[position] != 0x3E { position += 1 }
                while try nextAttribute(bytes, &position, end: end) != nil {}
                position += 1
            } else if next == 0x21 || next == 0x2F || next == 0x3F {
                while position < end, bytes[position] != 0x3E { position += 1 }
                if position >= end { return nil }
                position += 1
            } else {
                position += 1
            }
        }
        return nil
    }

    private enum MetaOutcome {
        case found(HTMLEncoding)
        case keepGoing
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }
    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
    }

    /// `<meta` in any case, followed by white space or a slash.
    private static func isMetaStart(_ bytes: [UInt8], at position: Int, end: Int) -> Bool {
        guard position + 5 < end else { return false }
        let word = Array("meta".utf8)
        for offset in 0 ..< 4 where bytes[position + 1 + offset] | 0x20 != word[offset] { return false }
        let after = bytes[position + 5]
        return isSpace(after) || after == 0x2F
    }

    /// The attributes of a `meta` start tag, until one gives an encoding that counts (the steps "attributes" and "processing" of the standard).
    private static func scanMeta(_ bytes: [UInt8], _ position: inout Int, end: Int) throws -> MetaOutcome {
        enum Charset {
            case unset, failure
            case found(HTMLEncoding)
        }
        var seen: [[UInt8]] = []
        var gotPragma = false
        var needPragma: Bool?
        var charset = Charset.unset
        while let (name, value) = try nextAttribute(bytes, &position, end: end) {
            if seen.contains(name) { continue }
            seen.append(name)
            if name.elementsEqual("http-equiv".utf8) {
                if value.elementsEqual("content-type".utf8) { gotPragma = true }
            } else if name.elementsEqual("content".utf8) {
                if case .unset = charset, let found = encodingInContent(value) {
                    charset = .found(found)
                    needPragma = true
                }
            } else if name.elementsEqual("charset".utf8) {
                charset = HTMLEncoding(label: value[...]).map(Charset.found) ?? .failure
                needPragma = false
            }
        }
        guard let needed = needPragma, !needed || gotPragma, case .found(var encoding) = charset else {
            return .keepGoing
        }
        if encoding == .utf16BE || encoding == .utf16LE { encoding = .utf8 }
        if encoding == .xUserDefined { encoding = .windows1252 }
        return .found(encoding)
    }

    private static func lowered(_ byte: UInt8) -> UInt8 { byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte }

    /// "Get an attribute" of the prescan: the name (lower case) and value (ASCII lower case) of the next attribute, or nil at the `>`.
    private static func nextAttribute(_ bytes: [UInt8], _ position: inout Int, end: Int) throws -> (
        name: [UInt8], value: [UInt8]
    )? {
        while position < end, isSpace(bytes[position]) || bytes[position] == 0x2F { position += 1 }
        guard position < end else { throw Exhausted() }
        guard bytes[position] != 0x3E else { return nil }
        var name: [UInt8] = []
        guard try readName(bytes, &position, end: end, into: &name) else { return (name, []) }
        return (name, try readValue(bytes, &position, end: end))
    }

    /// The name; false if the attribute ends with it (no `=` follows).
    private static func readName(_ bytes: [UInt8], _ position: inout Int, end: Int, into name: inout [UInt8]) throws
        -> Bool
    {
        while true {
            guard position < end else { throw Exhausted() }
            let byte = bytes[position]
            if byte == 0x3D, !name.isEmpty {
                position += 1
                return true
            }
            if isSpace(byte) {
                while position < end, isSpace(bytes[position]) { position += 1 }
                guard position < end else { throw Exhausted() }
                guard bytes[position] == 0x3D else { return false }
                position += 1
                return true
            }
            if byte == 0x2F || byte == 0x3E { return false }
            name.append(lowered(byte))
            position += 1
        }
    }

    /// The value after the `=`: quoted, or up to white space or `>`.
    private static func readValue(_ bytes: [UInt8], _ position: inout Int, end: Int) throws -> [UInt8] {
        var value: [UInt8] = []
        while position < end, isSpace(bytes[position]) { position += 1 }
        guard position < end else { throw Exhausted() }
        let first = bytes[position]
        if first == 0x22 || first == 0x27 {
            position += 1
            while position < end, bytes[position] != first {
                value.append(lowered(bytes[position]))
                position += 1
            }
            guard position < end else { throw Exhausted() }
            position += 1
            return value
        }
        if first == 0x3E { return value }
        while position < end, !isSpace(bytes[position]), bytes[position] != 0x3E {
            value.append(lowered(bytes[position]))
            position += 1
        }
        guard position < end else { throw Exhausted() }
        return value
    }

    /// "Extracting a character encoding from a `meta` element": the label after `charset=` in a `content` value such as `text/html; charset=windows-1251`.
    static func encodingInContent(_ content: [UInt8]) -> HTMLEncoding? {
        var position = 0
        let word = Array("charset".utf8)
        while true {
            // The first `charset` at or after `position`, in any case.
            var found: Int?
            var scan = position
            while scan + 7 <= content.count {
                if (0 ..< 7).allSatisfy({ content[scan + $0] | 0x20 == word[$0] }) {
                    found = scan
                    break
                }
                scan += 1
            }
            guard let start = found else { return nil }
            position = start + 7
            while position < content.count, isSpace(content[position]) { position += 1 }
            guard position < content.count, content[position] == 0x3D else { continue }
            position += 1
            while position < content.count, isSpace(content[position]) { position += 1 }
            guard position < content.count else { return nil }
            let quote = content[position]
            if quote == 0x22 || quote == 0x27 {
                guard let close = content[(position + 1)...].firstIndex(of: quote) else { return nil }
                return HTMLEncoding(label: content[(position + 1) ..< close])
            }
            var end = position
            while end < content.count, !isSpace(content[end]), content[end] != 0x3B { end += 1 }
            return HTMLEncoding(label: content[position ..< end])
        }
    }
}
