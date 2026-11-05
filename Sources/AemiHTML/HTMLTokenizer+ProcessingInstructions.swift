internal import AemiKernel
internal import AemiKernels

extension HTMLTokenizer {
    /// 13.2.5.72 to 13.2.5.76 (processing instructions, added to the HTML Standard in 2026): `<?` + a target, then data up to `?>` or `>`. A target the standard does not accept is a comment, whose data is the `?`
    /// and everything after it; `dataStart` is the `?`.
    mutating func processingInstructionStep() {
        switch state {
            case .processingInstructionOpen:
                let next = byte(pos)
                if Self.isAlpha(next) || next == 0x5F {
                    targetStart = pos
                    state = .processingInstructionTarget
                } else if next == -1 {
                    error(.eofInProcessingInstruction)
                    done = true
                } else {
                    error(.invalidFirstCharacterOfProcessingInstructionTarget)
                    state = .bogusComment
                }
            case .processingInstructionTarget: processingInstructionTargetState()
            case .afterProcessingInstructionTarget:
                while Self.isWhitespace(byte(pos)) { pos += 1 }
                dataStart = pos
                state = .processingInstructionData
            default: processingInstructionDataState()
        }
    }

    private mutating func processingInstructionTargetState() {
        while true {
            let next = byte(pos)
            if Self.isAlphanumeric(next) || next == 0x2D || next == 0x5F {
                pos += 1
                continue
            }
            if next == -1 {
                error(.eofInProcessingInstruction)
                done = true
            } else if Self.isWhitespace(next) || next == 0x3F || next == 0x3E {
                let length = pos - targetStart
                let isXML =
                    (length == 3 && matches("xml", at: targetStart))
                    || (length == 14 && matches("xml-stylesheet", at: targetStart))
                if isXML {
                    error(.disallowedProcessingInstructionTarget)
                    state = .bogusComment
                } else {
                    targetEnd = pos
                    state = .afterProcessingInstructionTarget
                }
            } else {
                error(.invalidProcessingInstructionTarget)
                state = .bogusComment
            }
            return
        }
    }

    /// The data, to the first `>`; a `?` just before it is the end's, not the data's.
    private mutating func processingInstructionDataState() {
        let stop = find(Stops.greaterThan, from: pos)
        guard stop < count else {
            pos = count
            error(.eofInProcessingInstruction)
            done = true
            return
        }
        var end = stop
        if end > dataStart, input[end - 1] == 0x3F { end -= 1 }
        append(tag: HTMLTokens.Tag.processingInstruction, aux: 0, low: out.tape.count + 3)
        append(tag: HTMLTokens.Tag.name, aux: (targetEnd - targetStart) << 1, low: targetStart)
        append(tag: HTMLTokens.Tag.value, aux: Swift.min(end - dataStart, HTMLTokens.maxLength) << 1, low: dataStart)
        pos = stop + 1
        state = .data
        batchReady = true
    }
}
