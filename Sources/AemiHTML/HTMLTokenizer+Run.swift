internal import AemiKernel
internal import AemiKernels

/// The byte sets the hot loops stop at. `ByteSet` is the SIMD search of `AemiKernels`.
enum Stops {
    static let data = set([0x3C, 0x26, 0x00])
    static let rawtext = set([0x3C, 0x00])
    static let plaintext = set([0x00])
    static let scriptNormal = set([0x3C, 0x00])
    static let scriptEscaped = set([0x3C, 0x2D, 0x3E, 0x00])
    static let doubleQuoted = set([0x22, 0x26, 0x00])
    static let singleQuoted = set([0x27, 0x26, 0x00])
    static let unquoted = set([0x09, 0x0A, 0x0C, 0x20, 0x26, 0x3E, 0x00, 0x22, 0x27, 0x3C, 0x3D, 0x60])
    static let tagName = set([0x09, 0x0A, 0x0C, 0x20, 0x2F, 0x3E, 0x00])
    static let attributeName = set([0x09, 0x0A, 0x0C, 0x20, 0x2F, 0x3E, 0x3D, 0x00, 0x22, 0x27, 0x3C])
    static let comment = set([0x3C, 0x2D, 0x00])
    static let bogus = set([0x3E, 0x00])
    static let identifierDouble = set([0x22, 0x3E, 0x00])
    static let identifierSingle = set([0x27, 0x3E, 0x00])
    static let cdata = set([0x5D])
    static let greaterThan = set([0x3E])

    private static func set(_ bytes: [UInt8]) -> AemiKernels.ByteSet {
        guard let found = AemiKernels.ByteSet(bytes) else { preconditionFailure("a stop set the kernel cannot hold") }
        return found
    }
}

extension HTMLTokenizer {
    // MARK: Reading

    /// The byte at `index`, or -1 past the end.
    @inline(__always) mutating func byte(_ index: Int) -> Int {
        if index < count { return Int(input[index]) }
        if !isFinal { touchedEnd = true }
        return -1
    }

    /// Notes that what the tokenizer is about to do depends on the input ending here: in a stream it will be undone and waited out, in a whole document nothing changes.
    @inline(__always) mutating func reachedEnd() {
        if !isFinal { touchedEnd = true }
    }

    /// The index of the first byte at or after `from` that is in `set`, or `count`.
    @inline(__always) func find(_ set: AemiKernels.ByteSet, from: Int) -> Int {
        guard from < count else { return count }
        return input.withUnsafeBufferPointer { buffer in
            // SAFETY: `from < count`, and the kernel reads `count - from` bytes from `from`, inside the buffer.
            guard let base = buffer.baseAddress else { return count }
            return unsafe from + AemiKernels.firstIndex(inSet: set, base: base + from, count: count - from)
        }
    }

    @inline(__always) static func isWhitespace(_ value: Int) -> Bool {
        value == 0x09 || value == 0x0A || value == 0x0C || value == 0x20
    }

    @inline(__always) static func isAlpha(_ value: Int) -> Bool {
        (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A)
    }

    @inline(__always) static func isAlphanumeric(_ value: Int) -> Bool {
        isAlpha(value) || (value >= 0x30 && value <= 0x39)
    }

    /// Whether the bytes at `index` are `word` in any case (`word` is lower case).
    mutating func matches(_ word: StaticString, at index: Int) -> Bool {
        guard index + word.utf8CodeUnitCount <= count else {
            reachedEnd()
            return false
        }
        for offset in 0 ..< word.utf8CodeUnitCount {
            var value = input[index + offset]
            if value >= 0x41, value <= 0x5A { value += 0x20 }
            if unsafe value != word.utf8Start[offset] { return false }
        }
        return true
    }

    // MARK: Writing

    mutating func error(_ code: HTMLParseError) {
        if options.collectsErrors { out.errors.append(HTMLTokens.Error(code: code, offset: pos)) }
    }

    mutating func append(tag: UInt8, aux: Int, low: Int) {
        out.tape.append(TapeSlot.make(tag: tag, aux: UInt64(aux), low: low))
    }

    /// Text from the source, `from ..< to`. A run of text is one slot: it joins the slot before when that is text, either by extending a range of the source that touches it, or, in a run that has had a reference decoded (it is
    /// in the scratch, at its end), by copying the source bytes after it.
    mutating func emitText(_ from: Int, _ to: Int, tag: UInt8 = HTMLTokens.Tag.text) {
        var from = from
        while from < to {
            let length = Swift.min(to - from, HTMLTokens.maxLength)
            if tag == HTMLTokens.Tag.text, out.tape.count > sealed, let last = out.tape.last, TapeSlot.tag(last) == tag
            {
                let aux = Int(TapeSlot.aux(last))
                let low = TapeSlot.low(last)
                let have = aux >> 1
                if have + length <= HTMLTokens.maxLength {
                    if aux & 1 == 0, low + have == from {
                        out.tape[out.tape.count - 1] = TapeSlot.make(
                            tag: tag,
                            aux: UInt64((have + length) << 1),
                            low: low
                        )
                        from += length
                        continue
                    }
                    if aux & 1 == 1, low + have == out.scratch.count {
                        out.scratch.append(contentsOf: input[from ..< from + length])
                        out.tape[out.tape.count - 1] = TapeSlot.make(
                            tag: tag,
                            aux: UInt64((have + length) << 1 | 1),
                            low: low
                        )
                        from += length
                        continue
                    }
                }
            }
            append(tag: tag, aux: length << 1, low: from)
            from += length
        }
    }

    /// A scalar the tokenizer made (a decoded reference, U+FFFD), as text: the text before it in the run moves to the scratch, if it is not there, so that the run stays one contiguous range.
    mutating func emitScalars(_ first: UInt32, _ second: UInt32? = nil) {
        var start = out.scratch.count
        if out.tape.count > sealed, let last = out.tape.last, TapeSlot.tag(last) == HTMLTokens.Tag.text {
            let aux = Int(TapeSlot.aux(last))
            let low = TapeSlot.low(last)
            let have = aux >> 1
            if have + 8 <= HTMLTokens.maxLength {
                if aux & 1 == 0 || low + have != start {
                    start = out.scratch.count
                    out.appendCopy(of: TapeSlot.make(tag: 0, aux: UInt64(aux), low: low))
                    out.tape[out.tape.count - 1] = TapeSlot.make(
                        tag: HTMLTokens.Tag.text,
                        aux: UInt64(have << 1 | 1),
                        low: start
                    )
                }
                let base = TapeSlot.low(out.tape[out.tape.count - 1])
                Self.encode(first, into: &out.scratch)
                if let second { Self.encode(second, into: &out.scratch) }
                let length = out.scratch.count - base
                out.tape[out.tape.count - 1] = TapeSlot.make(
                    tag: HTMLTokens.Tag.text,
                    aux: UInt64(length << 1 | 1),
                    low: base
                )
                return
            }
        }
        Self.encode(first, into: &out.scratch)
        if let second { Self.encode(second, into: &out.scratch) }
        append(tag: HTMLTokens.Tag.text, aux: (out.scratch.count - start) << 1 | 1, low: start)
    }

    static func encode(_ value: UInt32, into bytes: inout [UInt8]) {
        let scalar = Unicode.Scalar(value) ?? "\u{FFFD}"
        for unit in UTF8.encode(scalar) ?? UTF8.encode("\u{FFFD}")! { bytes.append(unit) }
    }

    /// The `aux` and `low` of a name for `from ..< to` of the source: the source itself if it has no upper-case letter and no NUL, else a lower-case copy in the scratch, NUL as U+FFFD.
    mutating func nameSlot(_ from: Int, _ to: Int, folds: Bool = true) -> (aux: Int, low: Int) {
        precondition(from >= 0 && to <= input.count, "a name lies inside the input")
        let plain = input.withUnsafeBufferPointer { buffer in
            var index = from
            while index < to {
                let value = unsafe buffer[index]
                if value == 0 || (folds && value >= 0x41 && value <= 0x5A) { return false }
                index += 1
            }
            return true
        }
        if plain { return (Swift.min(to - from, HTMLTokens.maxLength) << 1, from) }
        let start = out.scratch.count
        for position in from ..< to {
            let value = input[position]
            if value == 0 {
                Self.encode(0xFFFD, into: &out.scratch)
            } else if folds, value >= 0x41, value <= 0x5A {
                out.scratch.append(value + 0x20)
            } else {
                out.scratch.append(value)
            }
        }
        return (Swift.min(out.scratch.count - start, HTMLTokens.maxLength) << 1 | 1, start)
    }

    // MARK: Errors in the input stream

    /// The parse errors of the input stream (13.2.3.5): control characters and noncharacters, and surrogates that UTF-8 cannot hold (they cannot be in `[UInt8]` read as UTF-8, so not reported).
    mutating func scanInputErrors(from start: Int = 0) {
        var index = start
        while index < count {
            let lead = input[index]
            var value = UInt32(lead)
            var length = 1
            if lead >= 0xC0 {
                length = lead >= 0xF0 ? 4 : (lead >= 0xE0 ? 3 : 2)
                if index + length <= count {
                    value = UInt32(lead) & (0xFF >> (length + 1))
                    for offset in 1 ..< length { value = value << 6 | UInt32(input[index + offset] & 0x3F) }
                } else {
                    length = 1
                }
            }
            let at = pos
            pos = index
            if value != 0, value != 0x09, value != 0x0A, value != 0x0C, value != 0x0D, value != 0x20,
                value < 0x20 || (value >= 0x7F && value <= 0x9F)
            {
                error(.controlCharacterInInputStream)
            } else if (value >= 0xFDD0 && value <= 0xFDEF) || (value & 0xFFFE) == 0xFFFE, value <= 0x10FFFF {
                error(.noncharacterInInputStream)
            }
            pos = at
            index += length
        }
    }
}
