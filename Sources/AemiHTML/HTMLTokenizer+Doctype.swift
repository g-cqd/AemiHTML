internal import AemiKernel
internal import AemiKernels

extension HTMLTokenizer {
    /// A doctype token takes four slots at once: itself, its name, its public identifier and its system identifier (empty until set).
    mutating func beginDoctype() {
        doctypeSlot = out.tape.count
        doctypeFlags = []
        append(tag: HTMLTokens.Tag.doctype, aux: 0, low: 0)
        append(tag: HTMLTokens.Tag.name, aux: 0, low: 0)
        append(tag: HTMLTokens.Tag.value, aux: 0, low: 0)
        append(tag: HTMLTokens.Tag.value, aux: 0, low: 0)
        state = .doctype
    }

    mutating func emitDoctype() {
        out.tape[doctypeSlot] = TapeSlot.make(
            tag: HTMLTokens.Tag.doctype,
            aux: UInt64(doctypeFlags.rawValue),
            low: out.tape.count
        )
        state = .data
        batchReady = true
    }

    /// Sets the name (0), public identifier (1) or system identifier (2) from `dataStart ..< end`.
    mutating func setDoctypeString(_ which: Int, upTo end: Int) {
        let slot = nameSlot(dataStart, end, folds: which == 0)
        let tag = which == 0 ? HTMLTokens.Tag.name : HTMLTokens.Tag.value
        out.tape[doctypeSlot + 1 + which] = TapeSlot.make(tag: tag, aux: UInt64(slot.aux), low: slot.low)
    }

    mutating func doctypeEOF() {
        reachedEnd()
        error(.eofInDoctype)
        doctypeFlags.insert(.forcesQuirks)
        emitDoctype()
        done = true
    }

    /// A doctype that cannot go on: forced to quirks mode, and the rest of it is skipped to the `>`.
    mutating func doctypeBogus(_ code: HTMLParseError) {
        error(code)
        doctypeFlags.insert(.forcesQuirks)
        state = .bogusDoctype
    }

    mutating func doctypeEnd(_ code: HTMLParseError?) {
        if let code { error(code) }
        doctypeFlags.insert(.forcesQuirks)
        pos += 1
        emitDoctype()
    }

    /// At the opening quote of the public (1) or system (2) identifier.
    mutating func startIdentifier(_ which: Int) {
        doctypeFlags.insert(which == 1 ? .hasPublicIdentifier : .hasSystemIdentifier)
        attributeValueQuote = input[pos]
        pos += 1
        dataStart = pos
        state = which == 1 ? .doctypePublicIdentifier : .doctypeSystemIdentifier
    }

    mutating func doctypeStep() {
        switch state {
            case .doctype, .beforeDoctypeName, .doctypeName, .afterDoctypeName: doctypeNameStep()
            case .bogusDoctype: bogusDoctypeState()
            case .doctypePublicIdentifier, .doctypeSystemIdentifier: identifierState()
            default: doctypeIdentifierStep()
        }
    }

    mutating func doctypeNameStep() {
        let next = byte(pos)
        switch state {
            case .doctype:
                if next == -1 { return doctypeEOF() }
                if !Self.isWhitespace(next), next != 0x3E {
                    error(.missingWhitespaceBeforeDoctypeName)
                } else if next != 0x3E {
                    pos += 1
                }
                state = .beforeDoctypeName
            case .beforeDoctypeName:
                if Self.isWhitespace(next) {
                    pos += 1
                } else if next == -1 {
                    doctypeEOF()
                } else if next == 0x3E {
                    doctypeEnd(.missingDoctypeName)
                } else {
                    doctypeFlags.insert(.hasName)
                    dataStart = pos
                    state = .doctypeName
                }
            case .doctypeName:
                var end = pos
                while byte(end) != -1, !Self.isWhitespace(byte(end)), byte(end) != 0x3E { end += 1 }
                for index in pos ..< end where input[index] == 0 {
                    let at = pos
                    pos = index
                    error(.unexpectedNullCharacter)
                    pos = at
                }
                setDoctypeString(0, upTo: end)
                pos = end
                if byte(pos) == -1 { return doctypeEOF() }
                if byte(pos) == 0x3E {
                    pos += 1
                    emitDoctype()
                } else {
                    pos += 1
                    state = .afterDoctypeName
                }
            default: afterDoctypeNameState()
        }
    }

    mutating func afterDoctypeNameState() {
        while Self.isWhitespace(byte(pos)) { pos += 1 }
        let next = byte(pos)
        if next == 0x3E {
            pos += 1
            emitDoctype()
        } else if next == -1 {
            doctypeEOF()
        } else if matches("public", at: pos) {
            pos += 6
            state = .afterDoctypePublicKeyword
        } else if matches("system", at: pos) {
            pos += 6
            state = .afterDoctypeSystemKeyword
        } else {
            doctypeBogus(.invalidCharacterSequenceAfterDoctypeName)
        }
    }

    /// 13.2.5.67: after the doctype is spoiled, up to `>`.
    mutating func bogusDoctypeState() {
        while true {
            let next = byte(pos)
            if next == -1 {
                emitDoctype()
                done = true
                return
            }
            if next == 0x3E {
                pos += 1
                emitDoctype()
                return
            }
            if next == 0 { error(.unexpectedNullCharacter) }
            pos += 1
        }
    }

    /// 13.2.5.57 to 13.2.5.58 and 13.2.5.64 to 13.2.5.65: an identifier in quotes, to its closing quote.
    mutating func identifierState() {
        let isPublic = state == .doctypePublicIdentifier
        let quote = Int(attributeValueQuote)
        let stops = quote == 0x22 ? Stops.identifierDouble : Stops.identifierSingle
        var stop = find(stops, from: pos)
        while stop < count, input[stop] == 0 {
            pos = stop
            error(.unexpectedNullCharacter)
            stop = find(stops, from: stop + 1)
        }
        setDoctypeString(isPublic ? 1 : 2, upTo: stop)
        pos = stop
        switch byte(pos) {
            case -1: doctypeEOF()
            case 0x3E: doctypeEnd(isPublic ? .abruptDoctypePublicIdentifier : .abruptDoctypeSystemIdentifier)
            default:
                pos += 1
                state = isPublic ? .afterDoctypePublicIdentifier : .afterDoctypeSystemIdentifier
        }
    }
}
