internal import AemiKernel
internal import AemiKernels

extension HTMLTokenizer {
    /// Runs the state machine to the end of the input.
    mutating func run() {
        while !done { step() }
    }

    mutating func step() {
        switch state {
            case .data: dataState()
            case .rcdata, .rawtext: rawTextState()
            case .scriptData: scriptDataState()
            case .plaintext: plaintextState()
            case .cdata: cdataState()
            case .tagOpen, .endTagOpen, .tagName, .beforeAttributeName, .attributeName, .afterAttributeName,
                .beforeAttributeValue, .attributeValueQuoted, .attributeValueUnquoted, .afterAttributeValueQuoted,
                .selfClosingStartTag:
                tagStep()
            case .markupDeclarationOpen, .bogusComment, .commentStart, .commentStartDash, .comment, .commentEndDash,
                .commentEnd, .commentEndBang:
                commentStep()
            case .processingInstructionOpen, .processingInstructionTarget, .afterProcessingInstructionTarget,
                .processingInstructionData:
                processingInstructionStep()
            default: doctypeStep()
        }
    }

    /// A text state has used up the input: the document is over, or, in a stream, the text so far is complete and more may follow.
    mutating func textUsedUp() {
        if isFinal { done = true } else { needMore = true }
    }

    /// 13.2.5.1: text up to `<`, `&` or NUL.
    mutating func dataState() {
        let stop = find(Stops.data, from: pos)
        emitText(pos, stop)
        pos = stop
        markAfterText()
        guard pos < count else {
            textUsedUp()
            return
        }
        switch Int(input[pos]) {
            case 0x26:
                if !characterReference(inAttribute: false) {
                    emitText(pos, pos + 1)
                    pos += 1
                }
            case 0x3C:
                tagStart = pos
                pos += 1
                state = .tagOpen
            default:
                error(.unexpectedNullCharacter)
                emitText(pos, pos + 1)
                pos += 1
        }
    }

    /// 13.2.5.2 and 13.2.5.3: RCDATA and RAWTEXT. Text up to `<` (RCDATA also `&`, and NUL as U+FFFD), and the `</` + the last start tag's name that ends it. Everything else, `</p>` and `<b>`, is text.
    mutating func rawTextState() {
        let rcdata = state == .rcdata
        let stop = find(rcdata ? Stops.data : Stops.rawtext, from: pos)
        emitText(pos, stop)
        pos = stop
        markAfterText()
        guard pos < count else {
            textUsedUp()
            return
        }
        switch Int(input[pos]) {
            case 0x26:
                if !characterReference(inAttribute: false) {
                    emitText(pos, pos + 1)
                    pos += 1
                }
            case 0x3C:
                if let end = appropriateEndTag(at: pos) {
                    tagStart = pos
                    beginTag(isEnd: true)
                    setTagName(pos + 2, end)
                    pos = end
                    state = .beforeAttributeName
                } else {
                    emitText(pos, pos + 1)
                    pos += 1
                }
            default:
                error(.unexpectedNullCharacter)
                emitScalars(0xFFFD)
                pos += 1
        }
    }

    /// If `at` is `</` + the last start tag's name + whitespace, `/` or `>`, the index after the name.
    mutating func appropriateEndTag(at index: Int) -> Int? {
        let last = out.bytes(range: lastStartTagRange)
        let length = last.count
        guard length > 0 else { return nil }
        // The bytes that decide: `</`, the name, and the one after it.
        if index + 3 + length > count { reachedEnd() }
        guard byte(index + 1) == 0x2F, index + 2 + length <= count else { return nil }
        for offset in 0 ..< length {
            var value = input[index + 2 + offset]
            if value >= 0x41, value <= 0x5A { value += 0x20 }
            if value != last[last.startIndex + offset] { return nil }
        }
        let next = byte(index + 2 + length)
        guard Self.isWhitespace(next) || next == 0x2F || next == 0x3E else { return nil }
        return index + 2 + length
    }

    /// 13.2.5.5: everything is text; NUL is U+FFFD.
    mutating func plaintextState() {
        let stop = find(Stops.plaintext, from: pos)
        emitText(pos, stop)
        pos = stop
        guard pos < count else {
            textUsedUp()
            return
        }
        error(.unexpectedNullCharacter)
        emitScalars(0xFFFD)
        pos += 1
    }

    /// 13.2.5.69 to 13.2.5.71: a CDATA section is text up to `]]>`.
    mutating func cdataState() {
        var index = pos
        while true {
            index = find(Stops.cdata, from: index)
            if index >= count {
                if !isFinal {
                    // `]]` at the end may be the start of `]]>`: those two bytes wait.
                    var safe = Swift.max(pos, count - 2)
                    // Not inside a character: a token is whole characters.
                    while safe > pos, input[safe] & 0xC0 == 0x80 { safe -= 1 }
                    emitText(pos, safe)
                    pos = safe
                    needMore = true
                    return
                }
                emitText(pos, count)
                pos = count
                error(.eofInCdata)
                done = true
                return
            }
            if byte(index + 1) == 0x5D, byte(index + 2) == 0x3E {
                emitText(pos, index)
                pos = index + 3
                state = .data
                return
            }
            index += 1
        }
    }
}
