extension MarkdownWriter {
    static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
    }

    /// Text of the page: whitespace collapses to one space, and bytes that would be Markdown are escaped.
    mutating func writeText(_ bytes: ArraySlice<UInt8>) {
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            // U+00A0 reads as a space.
            if Self.isSpace(byte) || (byte == 0xC2 && index + 1 < bytes.endIndex && bytes[index + 1] == 0xA0) {
                pendingSpace = true
                index += byte == 0xC2 ? 2 : 1
                continue
            }
            flushMarks()
            beginLine()
            if pendingSpace, lineHasContent {
                out.append(0x20)
                previousByte = 0x20
            }
            pendingSpace = false
            let next: UInt8 = index + 1 < bytes.endIndex ? bytes[index + 1] : 0x20
            writeEscaped(byte, next: next)
            lineHasContent = true
            index += 1
        }
    }

    private func isAlphanumeric(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
            || byte >= 0x80
    }

    private mutating func writeEscaped(_ byte: UInt8, next: UInt8) {
        // `leadingDigits` counts the digits that are all the content of the line so far; -1 once something else came.
        if !lineHasContent { digitsAtLineStart = 0 }
        let onlyDigits = digitsAtLineStart
        defer {
            previousByte = byte
            digitsAtLineStart = (byte >= 0x30 && byte <= 0x39 && onlyDigits >= 0) ? onlyDigits + 1 : -1
        }
        guard markdown else {
            out.append(byte)
            return
        }
        let atStart = !lineHasContent
        var escape = false
        switch byte {
            case 0x5C, 0x60, 0x2A, 0x5B, 0x5D: escape = true
            case 0x5F: escape = !(isAlphanumeric(previousByte) && isAlphanumeric(next))
            case 0x3C: escape = isAlphanumeric(next) || next == 0x2F || next == 0x21 || next == 0x3F
            case 0x26: escape = isAlphanumeric(next) || next == 0x23
            case 0x7E: escape = true
            case 0x7C: escape = inline
            case 0x23, 0x3E, 0x3D: escape = atStart
            case 0x2B, 0x2D: escape = atStart && (next == 0x20 || next == 0x09 || next == byte)
            case 0x2E, 0x29: escape = onlyDigits > 0 && (next == 0x20 || next == 0x09)
            default: break
        }
        if escape { out.append(0x5C) }
        out.append(byte)
    }
}
