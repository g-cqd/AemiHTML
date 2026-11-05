internal import AemiKernel
internal import AemiKernels

extension HTMLTokenizer {
    mutating func beforeAttributeValueState() {
        while Self.isWhitespace(byte(pos)) { pos += 1 }
        switch byte(pos) {
            case 0x22, 0x27:
                attributeValueQuote = input[pos]
                pos += 1
                state = .attributeValueQuoted
            case 0x3E:
                error(.missingAttributeValue)
                pos += 1
                emitTag(selfClosing: false)
            default:
                attributeValueQuote = 0
                state = .attributeValueUnquoted
        }
    }

    /// A value being built from pieces, in the scratch: where it starts there, and where the source run not yet copied starts.
    struct ValueBuilder {
        var scratchBase = -1
        var runStart: Int
    }

    mutating func copyRun(_ builder: inout ValueBuilder, upTo end: Int) {
        if builder.scratchBase < 0 { builder.scratchBase = out.scratch.count }
        if end > builder.runStart {
            out.scratch.append(contentsOf: input[builder.runStart ..< end])
        }
    }

    /// 13.2.5.36 to 13.2.5.38: the value, to its quote or, unquoted, to whitespace or `>`. A value that holds a reference or a NUL is built in the scratch from its pieces; any other is a range of the source.
    mutating func attributeValueState() {
        let quote = attributeValueQuote
        let stops = quote == 0x22 ? Stops.doubleQuoted : (quote == 0x27 ? Stops.singleQuoted : Stops.unquoted)
        let start = pos
        var builder = ValueBuilder(runStart: pos)
        while true {
            let stop = find(stops, from: pos)
            pos = stop
            guard stop < count else {
                abandonTag()
                return
            }
            let value = input[stop]
            if quote != 0 ? value == quote : (Self.isWhitespace(Int(value)) || value == 0x3E) { break }
            switch value {
                case 0x26:
                    if let decoded = decodeReference(inAttribute: true) {
                        copyRun(&builder, upTo: stop)
                        Self.encode(decoded.first, into: &out.scratch)
                        if let second = decoded.second { Self.encode(second, into: &out.scratch) }
                        builder.runStart = pos
                    } else {
                        pos = stop + 1
                    }
                case 0x00:
                    error(.unexpectedNullCharacter)
                    copyRun(&builder, upTo: stop)
                    Self.encode(0xFFFD, into: &out.scratch)
                    pos = stop + 1
                    builder.runStart = pos
                default:
                    error(.unexpectedCharacterInUnquotedAttributeValue)
                    pos = stop + 1
            }
        }
        if builder.scratchBase >= 0 {
            copyRun(&builder, upTo: pos)
            let length = Swift.min(out.scratch.count - builder.scratchBase, HTMLTokens.maxLength)
            setAttributeValue(aux: length << 1 | 1, low: builder.scratchBase)
        } else {
            setAttributeValue(aux: Swift.min(pos - start, HTMLTokens.maxLength) << 1, low: start)
        }
        finishValue(quoted: quote != 0)
    }

    private mutating func finishValue(quoted: Bool) {
        if quoted {
            pos += 1
            state = .afterAttributeValueQuoted
        } else if byte(pos) == 0x3E {
            pos += 1
            emitTag(selfClosing: false)
        } else {
            pos += 1
            state = .beforeAttributeName
        }
    }
}
