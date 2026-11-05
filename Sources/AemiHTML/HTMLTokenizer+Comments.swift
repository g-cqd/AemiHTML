internal import AemiKernel
internal import AemiKernels

extension HTMLTokenizer {
    /// The comment `dataStart ..< dataEnd` of the source, with NUL as U+FFFD, as a token.
    mutating func emitComment() {
        let slot = nameSlot(dataStart, dataEnd, folds: false)
        append(tag: HTMLTokens.Tag.comment, aux: slot.aux, low: slot.low)
        state = .data
        batchReady = true
    }

    mutating func commentStep() {
        switch state {
            case .markupDeclarationOpen: markupDeclarationOpenState()
            case .bogusComment: bogusCommentState()
            case .commentStart: commentStartState()
            case .commentStartDash: commentStartDashState()
            case .comment: commentState()
            case .commentEndDash: commentEndDashState()
            case .commentEnd: commentEndState()
            default: commentEndBangState()
        }
    }

    /// 13.2.5.42: after `<!`: `--` opens a comment, `DOCTYPE` (any case) a doctype, `[CDATA[` a CDATA section where foreign content allows it; anything else is a bogus comment.
    mutating func markupDeclarationOpenState() {
        // The longest word to match is seven bytes: wait for them, or for the end.
        if pos + 7 > count { reachedEnd() }
        if byte(pos) == 0x2D, byte(pos + 1) == 0x2D {
            pos += 2
            dataStart = pos
            dataEnd = pos
            state = .commentStart
        } else if matches("doctype", at: pos) {
            pos += 7
            beginDoctype()
        } else if byte(pos) == 0x5B, pos + 7 <= count, input[pos ..< pos + 7].elementsEqual("[CDATA[".utf8) {
            if allowsCDATA {
                pos += 7
                state = .cdata
            } else {
                error(.cdataInHtmlContent)
                dataStart = pos
                state = .bogusComment
            }
        } else {
            error(.incorrectlyOpenedComment)
            dataStart = pos
            state = .bogusComment
        }
    }

    /// 13.2.5.41: up to the first `>`.
    mutating func bogusCommentState() {
        var stop = find(Stops.bogus, from: pos)
        while stop < count, input[stop] == 0 {
            pos = stop
            error(.unexpectedNullCharacter)
            stop = find(Stops.bogus, from: stop + 1)
        }
        dataEnd = stop
        pos = Swift.min(stop + 1, count)
        emitComment()
        if stop >= count {
            reachedEnd()
            done = true
        }
    }

    mutating func commentStartState() {
        switch byte(pos) {
            case 0x2D:
                pos += 1
                state = .commentStartDash
            case 0x3E:
                error(.abruptClosingOfEmptyComment)
                pos += 1
                emitComment()
            default: state = .comment
        }
    }

    mutating func commentStartDashState() {
        switch byte(pos) {
            case 0x2D:
                pos += 1
                state = .commentEnd
            case 0x3E:
                error(.abruptClosingOfEmptyComment)
                pos += 1
                dataEnd = dataStart
                emitComment()
            case -1: commentEOF()
            default:
                dataEnd = pos
                state = .comment
        }
    }

    mutating func commentEOF() {
        reachedEnd()
        error(.eofInComment)
        emitComment()
        done = true
    }

    /// 13.2.5.45 to 13.2.5.50: the body. `dataEnd` is where the data ends so far: a dash that may begin `-->` is not in it until something else follows.
    mutating func commentState() {
        let stop = find(Stops.comment, from: pos)
        if stop > pos { dataEnd = stop }
        pos = stop
        guard pos < count else {
            commentEOF()
            return
        }
        switch Int(input[pos]) {
            case 0x2D:
                pos += 1
                state = .commentEndDash
            case 0x00:
                error(.unexpectedNullCharacter)
                pos += 1
                dataEnd = pos
            default: lessThanInComment()
        }
    }

    /// 13.2.5.46 to 13.2.5.49: after `<`: `!` and then `--` is a nested comment opener, which is only an error when what follows is not `>`.
    private mutating func lessThanInComment() {
        pos += 1
        dataEnd = pos
        while byte(pos) == 0x3C {
            pos += 1
            dataEnd = pos
        }
        guard byte(pos) == 0x21 else { return }
        pos += 1
        dataEnd = pos
        guard byte(pos) == 0x2D else { return }
        pos += 1
        guard byte(pos) == 0x2D else {
            state = .commentEndDash
            return
        }
        pos += 1
        let next = byte(pos)
        if next != 0x3E, next != -1 { error(.nestedComment) }
        state = .commentEnd
    }

    mutating func commentEndDashState() {
        switch byte(pos) {
            case 0x2D:
                pos += 1
                state = .commentEnd
            case -1: commentEOF()
            default:
                dataEnd = pos
                state = .comment
        }
    }

    mutating func commentEndState() {
        switch byte(pos) {
            case 0x3E:
                pos += 1
                emitComment()
            case 0x21:
                pos += 1
                state = .commentEndBang
            case 0x2D:
                pos += 1
                dataEnd = pos - 2
            case -1: commentEOF()
            default:
                dataEnd = pos
                state = .comment
        }
    }

    mutating func commentEndBangState() {
        switch byte(pos) {
            case 0x2D:
                pos += 1
                dataEnd = pos - 1
                state = .commentEndDash
            case 0x3E:
                error(.incorrectlyClosedComment)
                pos += 1
                emitComment()
            case -1: commentEOF()
            default:
                dataEnd = pos
                state = .comment
        }
    }
}
