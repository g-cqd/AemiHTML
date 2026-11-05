extension HTMLDecoder {
    /// Shift_JIS (Encoding Standard 14.2): a lead byte and a trail byte, into the JIS X 0208 index; the lead bytes 0xF0 ... 0xF9 are the user-defined area (U+E000 ...).
    static func decodeShiftJIS(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        let index = EncodingIndexes.jis0208
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
                var found: UInt32?
                if (0x40 ... 0x7E).contains(byte) || (0x80 ... 0xFC).contains(byte) {
                    let offset = byte < 0x7F ? 0x40 : 0x41
                    let leadOffset = first < 0xA0 ? 0x81 : 0xC1
                    let pointer = (first - leadOffset) * 188 + Int(byte) - offset
                    if (8836 ... 10715).contains(pointer) {
                        found = UInt32(0xE000 - 8836 + pointer)
                    } else if pointer >= 0, pointer < index.count, index[pointer] != none {
                        found = index[pointer]
                    }
                }
                if let found {
                    put(found, &out)
                } else {
                    if byte < 0x80 { position -= 1 }
                    put(0xFFFD, &out)
                }
            } else if byte <= 0x80 {
                put(UInt32(byte), &out)
            } else if byte >= 0xA1 && byte <= 0xDF {
                put(0xFF61 - 0xA1 + UInt32(byte), &out)
            } else if (0x81 ... 0x9F).contains(byte) || (0xE0 ... 0xFC).contains(byte) {
                lead = byte
            } else {
                put(0xFFFD, &out)
            }
        }
        if lead != 0 { put(0xFFFD, &out) }
        return out
    }

    /// EUC-JP (14.1): JIS X 0208 by two bytes, JIS X 0212 after 0x8F, half-width katakana after 0x8E.
    static func decodeEUCJP(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        let jis0208 = EncodingIndexes.jis0208
        let jis0212 = EncodingIndexes.jis0212
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count * 2)
        var lead: UInt8 = 0
        var isJIS0212 = false
        var position = bytes.startIndex
        while position < bytes.endIndex {
            let byte = bytes[position]
            position += 1
            if lead == 0x8E, byte >= 0xA1, byte <= 0xDF {
                lead = 0
                put(0xFF61 - 0xA1 + UInt32(byte), &out)
            } else if lead == 0x8F, byte >= 0xA1, byte <= 0xFE {
                isJIS0212 = true
                lead = byte
            } else if lead != 0 {
                let first = Int(lead)
                lead = 0
                var found: UInt32?
                if first >= 0xA1, first <= 0xFE, byte >= 0xA1, byte <= 0xFE {
                    let pointer = (first - 0xA1) * 94 + Int(byte) - 0xA1
                    let table = isJIS0212 ? jis0212 : jis0208
                    if pointer < table.count, table[pointer] != none { found = table[pointer] }
                }
                isJIS0212 = false
                if let found {
                    put(found, &out)
                } else {
                    if byte < 0x80 { position -= 1 }
                    put(0xFFFD, &out)
                }
            } else if byte < 0x80 {
                put(UInt32(byte), &out)
            } else if byte == 0x8E || byte == 0x8F || (byte >= 0xA1 && byte <= 0xFE) {
                lead = byte
            } else {
                put(0xFFFD, &out)
            }
        }
        if lead != 0 { put(0xFFFD, &out) }
        return out
    }

    /// ISO-2022-JP (14.3): escape sequences switch between ASCII, JIS Roman, half-width katakana and JIS X 0208.
    static func decodeISO2022JP(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        var machine = ISO2022JP()
        machine.out.reserveCapacity(bytes.count * 2)
        var position = bytes.startIndex
        // The end of the input is one more step, with no byte.
        while machine.state != .finished {
            let byte: UInt8? = position < bytes.endIndex ? bytes[position] : nil
            if byte != nil { position += 1 }
            position -= machine.step(byte)
        }
        return machine.out
    }
}

/// The decoder state of ISO-2022-JP.
private struct ISO2022JP {
    enum State { case ascii, roman, katakana, leadByte, trailByte, escapeStart, escape, finished }

    static let index = EncodingIndexes.jis0208
    var state = State.ascii
    var outputState = State.ascii
    var lead: UInt8 = 0
    var outputFlag = false
    var out: [UInt8] = []

    private mutating func emit(_ value: UInt32) { HTMLDecoder.put(value, &out) }

    /// One step on `byte` (nil at the end): the decoder's rule for its state. Returns how many of the bytes just read are to be read again.
    mutating func step(_ byte: UInt8?) -> Int {
        guard let byte else {
            // The end: in the states that hold a half-read thing, it is an error; then the decoder is done.
            if state == .trailByte || state == .escapeStart { emit(0xFFFD) }
            if state == .escape {
                state = outputState
                outputFlag = false
                emit(0xFFFD)
                return 1
            }
            state = .finished
            return 0
        }
        if byte == 0x1B, state == .ascii || state == .roman || state == .katakana || state == .leadByte {
            state = .escapeStart
            return 0
        }
        switch state {
            case .ascii, .roman: single(byte)
            case .katakana: katakana(byte)
            case .leadByte:
                outputFlag = false
                if byte >= 0x21, byte <= 0x7E {
                    lead = byte
                    state = .trailByte
                } else {
                    emit(0xFFFD)
                }
            case .trailByte: return trail(byte)
            case .escapeStart: return escapeStart(byte)
            case .escape: return escape(byte)
            case .finished: break
        }
        return 0
    }

    private mutating func single(_ byte: UInt8) {
        outputFlag = false
        if state == .roman, byte == 0x5C {
            emit(0xA5)
        } else if state == .roman, byte == 0x7E {
            emit(0x203E)
        } else if byte <= 0x7F, byte != 0x0E, byte != 0x0F {
            emit(UInt32(byte))
        } else {
            emit(0xFFFD)
        }
    }

    private mutating func katakana(_ byte: UInt8) {
        outputFlag = false
        if byte >= 0x21, byte <= 0x5F { emit(0xFF61 - 0x21 + UInt32(byte)) } else { emit(0xFFFD) }
    }

    private mutating func trail(_ byte: UInt8) -> Int {
        if byte == 0x1B {
            state = .escapeStart
            emit(0xFFFD)
            return 0
        }
        state = .leadByte
        guard byte >= 0x21, byte <= 0x7E else {
            emit(0xFFFD)
            return 0
        }
        let pointer = (Int(lead) - 0x21) * 94 + Int(byte) - 0x21
        if pointer < Self.index.count, Self.index[pointer] != HTMLDecoder.none {
            emit(Self.index[pointer])
        } else {
            emit(0xFFFD)
        }
        return 0
    }

    private mutating func escapeStart(_ byte: UInt8) -> Int {
        if byte == 0x24 || byte == 0x28 {
            lead = byte
            state = .escape
            return 0
        }
        // Not the start of a sequence: the byte is read again, as what it is.
        outputFlag = false
        state = outputState
        emit(0xFFFD)
        return 1
    }

    private mutating func escape(_ byte: UInt8) -> Int {
        let first = lead
        lead = 0
        var next: State?
        switch (first, byte) {
            case (0x28, 0x42): next = .ascii
            case (0x28, 0x4A): next = .roman
            case (0x28, 0x49): next = .katakana
            case (0x24, 0x40), (0x24, 0x42): next = .leadByte
            default: break
        }
        if let next {
            state = next
            outputState = next
            if outputFlag { emit(0xFFFD) } else { outputFlag = true }
            return 0
        }
        // Not an escape sequence: both bytes are read again.
        outputFlag = false
        state = outputState
        emit(0xFFFD)
        return 2
    }
}
