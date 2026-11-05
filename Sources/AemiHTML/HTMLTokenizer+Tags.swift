internal import AemiKernel
internal import AemiKernels

extension HTMLTokenizer {
    // MARK: Building a tag

    mutating func beginTag(isEnd: Bool) {
        tagIsEnd = isEnd
        tagSlot = out.tape.count
        append(tag: isEnd ? HTMLTokens.Tag.endTag : HTMLTokens.Tag.startTag, aux: 0, low: 0)
        append(tag: HTMLTokens.Tag.name, aux: 0, low: 0)
        attributeCount = 0
        attributeNames.removeAll(keepingCapacity: true)
        attributeIsDuplicate = false
    }

    mutating func setTagName(_ from: Int, _ to: Int) {
        let slot = nameSlot(from, to)
        out.tape[tagSlot + 1] = TapeSlot.make(tag: HTMLTokens.Tag.name, aux: UInt64(slot.aux), low: slot.low)
    }

    /// The tag is cut short by the end of the input: it is dropped.
    mutating func abandonTag() {
        out.tape.removeLast(out.tape.count - tagSlot)
        error(.eofInTag)
        done = true
    }

    /// An attribute that repeats a name, or comes after the 4,095th, is taken out of the tag when the next begins.
    mutating func resolveDuplicate() {
        if attributeIsDuplicate {
            out.tape.removeLast(2)
            attributeIsDuplicate = false
        }
    }

    mutating func beginAttribute(at start: Int) {
        resolveDuplicate()
        attributeNameStart = start
    }

    mutating func finishAttributeName(_ from: Int, _ to: Int) {
        let slot = nameSlot(from, to)
        let name = nameBytes(slot)
        var repeated = attributeCount >= HTMLTokens.maxAttributes
        if !repeated {
            if attributeCount >= 8 {
                if attributeNames.isEmpty {
                    for number in 0 ..< attributeCount {
                        attributeNames.insert(Array(out.bytes(ofSlot: tagSlot + 2 + number * 2)))
                    }
                }
                repeated = !attributeNames.insert(name).inserted
            } else {
                for number in 0 ..< attributeCount where out.bytes(ofSlot: tagSlot + 2 + number * 2).elementsEqual(name)
                {
                    repeated = true
                    break
                }
            }
            if repeated { error(.duplicateAttribute) }
        }
        append(tag: HTMLTokens.Tag.name, aux: slot.aux, low: slot.low)
        append(tag: HTMLTokens.Tag.value, aux: 0, low: 0)
        attributeIsDuplicate = repeated
        if !repeated { attributeCount += 1 }
    }

    private func nameBytes(_ slot: (aux: Int, low: Int)) -> [UInt8] {
        let length = slot.aux >> 1
        return slot.aux & 1 == 0
            ? Array(out.source[slot.low ..< slot.low + length]) : Array(out.scratch[slot.low ..< slot.low + length])
    }

    mutating func setAttributeValue(aux: Int, low: Int) {
        out.tape[out.tape.count - 1] = TapeSlot.make(tag: HTMLTokens.Tag.value, aux: UInt64(aux), low: low)
    }

    /// The tag is complete: its slots are patched, and the content model switches if it is a start tag that needs it.
    mutating func emitTag(selfClosing: Bool) {
        resolveDuplicate()
        if tagIsEnd {
            if attributeCount > 0 { error(.endTagWithAttributes) }
            if selfClosing { error(.endTagWithTrailingSolidus) }
        }
        let aux = UInt64(attributeCount) | (selfClosing ? HTMLTokens.selfClosingFlag : 0)
        let kind = tagIsEnd ? HTMLTokens.Tag.endTag : HTMLTokens.Tag.startTag
        out.tape[tagSlot] = TapeSlot.make(tag: kind, aux: aux, low: out.tape.count)
        state = .data
        guard !tagIsEnd else { return }
        lastStartTag = Array(out.bytes(ofSlot: tagSlot + 1))
        if options.switchesContentModel { state = Self.contentModel(after: lastStartTag) }
    }

    /// The content model a start tag switches to (13.2.5.1 to 13.2.5.5, as a tree builder sets it).
    static func contentModel(after name: [UInt8]) -> State {
        switch String(decoding: name, as: UTF8.self) {
            case "textarea", "title": .rcdata
            case "style", "xmp", "iframe", "noembed", "noframes": .rawtext
            case "script": .scriptData
            case "plaintext": .plaintext
            default: .data
        }
    }

    // MARK: States

    mutating func tagStep() {
        switch state {
            case .tagOpen: tagOpenState()
            case .endTagOpen: endTagOpenState()
            case .tagName: tagNameState()
            case .beforeAttributeName: beforeAttributeNameState()
            case .attributeName: attributeNameState()
            case .afterAttributeName: afterAttributeNameState()
            case .beforeAttributeValue: beforeAttributeValueState()
            case .attributeValueQuoted, .attributeValueUnquoted: attributeValueState()
            case .afterAttributeValueQuoted: afterAttributeValueQuotedState()
            default: selfClosingStartTagState()
        }
    }

    mutating func tagOpenState() {
        let next = byte(pos)
        switch next {
            case 0x21:
                pos += 1
                state = .markupDeclarationOpen
            case 0x2F:
                pos += 1
                state = .endTagOpen
            case 0x3F:
                dataStart = pos
                pos += 1
                state = .processingInstructionOpen
            case -1:
                error(.eofBeforeTagName)
                emitText(tagStart, tagStart + 1)
                done = true
            default:
                if Self.isAlpha(next) {
                    beginTag(isEnd: false)
                    dataStart = pos
                    state = .tagName
                } else {
                    error(.invalidFirstCharacterOfTagName)
                    emitText(tagStart, tagStart + 1)
                    state = .data
                }
        }
    }

    mutating func endTagOpenState() {
        let next = byte(pos)
        switch next {
            case 0x3E:
                error(.missingEndTagName)
                pos += 1
                state = .data
            case -1:
                error(.eofBeforeTagName)
                emitText(tagStart, tagStart + 2)
                done = true
            default:
                if Self.isAlpha(next) {
                    beginTag(isEnd: true)
                    dataStart = pos
                    state = .tagName
                } else {
                    error(.invalidFirstCharacterOfTagName)
                    dataStart = pos
                    state = .bogusComment
                }
        }
    }

    mutating func tagNameState() {
        var stop = find(Stops.tagName, from: pos)
        while stop < count, input[stop] == 0 {
            pos = stop
            error(.unexpectedNullCharacter)
            stop = find(Stops.tagName, from: stop + 1)
        }
        guard stop < count else {
            pos = count
            abandonTag()
            return
        }
        setTagName(dataStart, stop)
        pos = stop + 1
        switch Int(input[stop]) {
            case 0x2F: state = .selfClosingStartTag
            case 0x3E: emitTag(selfClosing: false)
            default: state = .beforeAttributeName
        }
    }

    mutating func beforeAttributeNameState() {
        while Self.isWhitespace(byte(pos)) { pos += 1 }
        switch byte(pos) {
            case 0x2F, 0x3E, -1: state = .afterAttributeName
            case 0x3D:
                error(.unexpectedEqualsSignBeforeAttributeName)
                beginAttribute(at: pos)
                pos += 1
                state = .attributeName
            default:
                beginAttribute(at: pos)
                state = .attributeName
        }
    }

    mutating func attributeNameState() {
        var stop = find(Stops.attributeName, from: pos)
        while stop < count {
            let value = input[stop]
            if value == 0 {
                pos = stop
                error(.unexpectedNullCharacter)
            } else if value == 0x22 || value == 0x27 || value == 0x3C {
                pos = stop
                error(.unexpectedCharacterInAttributeName)
            } else {
                break
            }
            stop = find(Stops.attributeName, from: stop + 1)
        }
        finishAttributeName(attributeNameStart, stop)
        pos = stop
        if byte(pos) == 0x3D {
            pos += 1
            state = .beforeAttributeValue
        } else {
            state = .afterAttributeName
        }
    }

    mutating func afterAttributeNameState() {
        while Self.isWhitespace(byte(pos)) { pos += 1 }
        switch byte(pos) {
            case 0x2F:
                pos += 1
                state = .selfClosingStartTag
            case 0x3D:
                pos += 1
                state = .beforeAttributeValue
            case 0x3E:
                pos += 1
                emitTag(selfClosing: false)
            case -1: abandonTag()
            default:
                beginAttribute(at: pos)
                state = .attributeName
        }
    }

    mutating func selfClosingStartTagState() {
        switch byte(pos) {
            case 0x3E:
                pos += 1
                emitTag(selfClosing: true)
            case -1: abandonTag()
            default:
                error(.unexpectedSolidusInTag)
                state = .beforeAttributeName
        }
    }

    mutating func afterAttributeValueQuotedState() {
        switch byte(pos) {
            case 0x09, 0x0A, 0x0C, 0x20:
                pos += 1
                state = .beforeAttributeName
            case 0x2F:
                pos += 1
                state = .selfClosingStartTag
            case 0x3E:
                pos += 1
                emitTag(selfClosing: false)
            case -1: abandonTag()
            default:
                error(.missingWhitespaceBetweenAttributes)
                state = .beforeAttributeName
        }
    }
}
