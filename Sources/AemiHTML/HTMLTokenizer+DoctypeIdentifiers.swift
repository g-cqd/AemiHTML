internal import AemiKernel
internal import AemiKernels

extension HTMLTokenizer {
    /// The doctype states between and around the identifiers (13.2.5.55 to 13.2.5.66).
    mutating func doctypeIdentifierStep() {
        let wasWhitespaceSkipping =
            state == .beforeDoctypePublicIdentifier || state == .betweenDoctypeIdentifiers
            || state == .beforeDoctypeSystemIdentifier || state == .afterDoctypeSystemIdentifier
        if wasWhitespaceSkipping { while Self.isWhitespace(byte(pos)) { pos += 1 } }
        let next = byte(pos)
        let isQuote = next == 0x22 || next == 0x27
        if next == -1 { return doctypeEOF() }
        switch state {
            case .afterDoctypePublicKeyword:
                if Self.isWhitespace(next) {
                    pos += 1
                    state = .beforeDoctypePublicIdentifier
                } else if isQuote {
                    error(.missingWhitespaceAfterDoctypePublicKeyword)
                    startIdentifier(1)
                } else if next == 0x3E {
                    doctypeEnd(.missingDoctypePublicIdentifier)
                } else {
                    doctypeBogus(.missingQuoteBeforeDoctypePublicIdentifier)
                }
            case .beforeDoctypePublicIdentifier:
                if isQuote {
                    startIdentifier(1)
                } else if next == 0x3E {
                    doctypeEnd(.missingDoctypePublicIdentifier)
                } else {
                    doctypeBogus(.missingQuoteBeforeDoctypePublicIdentifier)
                }
            case .afterDoctypePublicIdentifier:
                if Self.isWhitespace(next) {
                    pos += 1
                    state = .betweenDoctypeIdentifiers
                } else if next == 0x3E {
                    pos += 1
                    emitDoctype()
                } else if isQuote {
                    error(.missingWhitespaceBetweenDoctypePublicAndSystemIdentifiers)
                    startIdentifier(2)
                } else {
                    doctypeBogus(.missingQuoteBeforeDoctypeSystemIdentifier)
                }
            case .betweenDoctypeIdentifiers:
                if next == 0x3E {
                    pos += 1
                    emitDoctype()
                } else if isQuote {
                    startIdentifier(2)
                } else {
                    doctypeBogus(.missingQuoteBeforeDoctypeSystemIdentifier)
                }
            default: doctypeSystemSide(next, isQuote: isQuote)
        }
    }

    private mutating func doctypeSystemSide(_ next: Int, isQuote: Bool) {
        switch state {
            case .afterDoctypeSystemKeyword:
                if Self.isWhitespace(next) {
                    pos += 1
                    state = .beforeDoctypeSystemIdentifier
                } else if isQuote {
                    error(.missingWhitespaceAfterDoctypeSystemKeyword)
                    startIdentifier(2)
                } else if next == 0x3E {
                    doctypeEnd(.missingDoctypeSystemIdentifier)
                } else {
                    doctypeBogus(.missingQuoteBeforeDoctypeSystemIdentifier)
                }
            case .beforeDoctypeSystemIdentifier:
                if isQuote {
                    startIdentifier(2)
                } else if next == 0x3E {
                    doctypeEnd(.missingDoctypeSystemIdentifier)
                } else {
                    doctypeBogus(.missingQuoteBeforeDoctypeSystemIdentifier)
                }
            default:
                if next == 0x3E {
                    pos += 1
                    emitDoctype()
                } else {
                    error(.unexpectedCharacterAfterDoctypeSystemIdentifier)
                    state = .bogusDoctype
                }
        }
    }
}
