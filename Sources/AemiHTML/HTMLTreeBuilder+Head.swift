internal import AemiKernel

extension HTMLTreeBuilder {
    // MARK: initial (13.2.6.4.1)

    mutating func initial(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character where token.characterClass == .whitespace: return .consumed
            case .comment:
                insertComment(token.text, at: Place(parent: document.root, before: .none))
                return .consumed
            case .processingInstruction:
                insertProcessingInstruction(token, at: Place(parent: document.root, before: .none))
                return .consumed
            case .doctype:
                handleDoctype(token)
                mode = .beforeHTML
                return .consumed
            default:
                document.quirksMode = .quirks
                mode = .beforeHTML
                return .reprocess
        }
    }

    mutating func handleDoctype(_ token: BuilderToken) {
        let slot = tokenizer.out.tape[token.index]
        let flags = HTMLDoctypeFlags(rawValue: Int(TapeSlot.aux(slot)))
        func range(_ at: Int) -> UInt64 {
            let value = tokenizer.out.tape[at]
            return TapeSlot.make(tag: 0, aux: TapeSlot.aux(value), low: TapeSlot.low(value))
        }
        let name = flags.contains(.hasName) ? range(token.index + 1) : 0
        let publicID = flags.contains(.hasPublicIdentifier) ? range(token.index + 2) : 0
        let systemID = flags.contains(.hasSystemIdentifier) ? range(token.index + 3) : 0
        let node = document.makeNode(.doctype, nameRange: name, dataRange: publicID)
        document.systemIdentifier = systemID
        if document.doctype.isNone {
            document.append(node, to: document.root)
            document.doctype = node
        }
        let publicBytes = Array(tokenizer.out.bytes(range: publicID)).map(Self.lower)
        let systemBytes = Array(tokenizer.out.bytes(range: systemID)).map(Self.lower)
        let isHTML = tokenizer.out.bytes(range: name).elementsEqual("html".utf8)
        document.quirksMode = Self.quirks(
            forcesQuirks: flags.contains(.forcesQuirks),
            isHTML: isHTML,
            publicID: publicBytes,
            systemID: systemBytes,
            hasPublic: flags.contains(.hasPublicIdentifier),
            hasSystem: flags.contains(.hasSystemIdentifier)
        )
    }

    static func lower(_ byte: UInt8) -> UInt8 { byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte }

    /// The mode a doctype sets (13.2.6.4.1); the strings are compared in lower case.
    static func quirks(
        forcesQuirks: Bool,
        isHTML: Bool,
        publicID: [UInt8],
        systemID: [UInt8],
        hasPublic: Bool,
        hasSystem: Bool
    ) -> HTMLDocument.QuirksMode {
        func starts(_ list: [[UInt8]]) -> Bool { list.contains { publicID.starts(with: $0) } }
        if forcesQuirks || !isHTML { return .quirks }
        if hasPublic, QuirksTables.quirksPublicExact.contains(publicID) { return .quirks }
        if hasSystem, QuirksTables.quirksSystemExact.contains(systemID) { return .quirks }
        if hasPublic, starts(QuirksTables.quirksPublicPrefixes) { return .quirks }
        if !hasSystem || systemID.isEmpty, hasPublic, starts(QuirksTables.quirksPrefixesIfSystemMissing) {
            return .quirks
        }
        if hasPublic, starts(QuirksTables.limitedPublicPrefixes) { return .limitedQuirks }
        if hasSystem, !systemID.isEmpty, hasPublic, starts(QuirksTables.limitedPrefixesIfSystemPresent) {
            return .limitedQuirks
        }
        return .noQuirks
    }

    // MARK: before html (13.2.6.4.2)

    mutating func beforeHTML(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .doctype: return .consumed
            case .comment:
                insertComment(token.text, at: Place(parent: document.root, before: .none))
                return .consumed
            case .processingInstruction:
                insertProcessingInstruction(token, at: Place(parent: document.root, before: .none))
                return .consumed
            case .character where token.characterClass == .whitespace: return .consumed
            case .startTag where token.name == .html:
                let node = createElement(tokenIndex: token.index, space: .html)
                document.append(node, to: document.root)
                push(node)
                mode = .beforeHead
                return .consumed
            case .endTag where token.name != .head && token.name != .body && token.name != .html && token.name != .br:
                return .consumed
            default:
                let node = document.makeNode(
                    .element,
                    name: .html,
                    space: .html,
                    nameRange: tokenizer.out.intern(utf8: "html")
                )
                document.append(node, to: document.root)
                push(node)
                mode = .beforeHead
                return .reprocess
        }
    }

    // MARK: before head (13.2.6.4.3)

    mutating func beforeHead(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character where token.characterClass == .whitespace: return .consumed
            case .comment:
                insertComment(token.text)
                return .consumed
            case .processingInstruction:
                insertProcessingInstruction(token)
                return .consumed
            case .doctype: return .consumed
            case .startTag where token.name == .html: return inBody(&token)
            case .startTag where token.name == .head:
                headPointer = insertHTMLElement(token)
                mode = .inHead
                return .consumed
            case .endTag where token.name != .head && token.name != .body && token.name != .html && token.name != .br:
                return .consumed
            default:
                headPointer = insertFakeElement(.head, "head")
                mode = .inHead
                return .reprocess
        }
    }

    // MARK: in head (13.2.6.4.4)

    mutating func inHead(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character where token.characterClass == .whitespace:
                insertCharacters(token.text)
                return .consumed
            case .comment:
                insertComment(token.text)
                return .consumed
            case .processingInstruction:
                insertProcessingInstruction(token)
                return .consumed
            case .doctype: return .consumed
            case .startTag: return inHeadStartTag(&token)
            case .endTag: return inHeadEndTag(&token)
            default:
                pop()
                mode = .afterHead
                return .reprocess
        }
    }

    private mutating func inHeadStartTag(_ token: inout BuilderToken) -> Disposition {
        switch token.name {
            case .html: return inBody(&token)
            case .base, .basefont, .bgsound, .link, .meta:
                insertHTMLElement(token)
                popJustInserted()
                acknowledge(&token)
            case .title: parseRawText(token, rcdata: true)
            case .noscript where scripting: parseRawText(token, rcdata: false)
            case .noframes, .style: parseRawText(token, rcdata: false)
            case .noscript:
                insertHTMLElement(token)
                mode = .inHeadNoscript
            case .script:
                insertHTMLElement(token)
                tokenizer.switchTo(.scriptData)
                originalMode = mode
                mode = .text
            case .template:
                insertMarker()
                framesetOK = false
                mode = .inTemplate
                templateModes.append(.inTemplate)
                insertHTMLElement(token)
            case .head: break
            default:
                pop()
                mode = .afterHead
                return .reprocess
        }
        return .consumed
    }

    private mutating func inHeadEndTag(_ token: inout BuilderToken) -> Disposition {
        switch token.name {
            case .head:
                pop()
                mode = .afterHead
            case .template:
                guard hasTemplateOnStack else { return .consumed }
                generateAllImpliedEndTagsThoroughly()
                popUntilHTML(.template)
                clearFormattingToMarker()
                templateModes.removeLast()
                resetInsertionMode()
            case .body, .html, .br:
                pop()
                mode = .afterHead
                return .reprocess
            default: break
        }
        return .consumed
    }

    // MARK: in head noscript (13.2.6.4.5)

    mutating func inHeadNoscript(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .doctype: return .consumed
            case .startTag where token.name == .html: return inBody(&token)
            case .endTag where token.name == .noscript:
                pop()
                mode = .inHead
                return .consumed
            case .character where token.characterClass == .whitespace, .comment, .processingInstruction:
                return inHead(&token)
            case .startTag where [.basefont, .bgsound, .link, .meta, .noframes, .style].contains(token.name):
                return inHead(&token)
            case .endTag where token.name != .br: return .consumed
            case .startTag where token.name == .head || token.name == .noscript: return .consumed
            default:
                pop()
                mode = .inHead
                return .reprocess
        }
    }

    // MARK: after head (13.2.6.4.6)

    mutating func afterHead(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character where token.characterClass == .whitespace:
                insertCharacters(token.text)
                return .consumed
            case .comment:
                insertComment(token.text)
                return .consumed
            case .processingInstruction:
                insertProcessingInstruction(token)
                return .consumed
            case .doctype: return .consumed
            case .startTag: return afterHeadStartTag(&token)
            case .endTag:
                switch token.name {
                    case .template: return inHead(&token)
                    case .body, .html, .br: break
                    default: return .consumed
                }
            default: break
        }
        insertFakeElement(.body, "body")
        framesetOK = true
        mode = .inBody
        return .reprocess
    }

    private mutating func afterHeadStartTag(_ token: inout BuilderToken) -> Disposition {
        switch token.name {
            case .html: return inBody(&token)
            case .body:
                insertHTMLElement(token)
                framesetOK = false
                mode = .inBody
            case .frameset:
                insertHTMLElement(token)
                mode = .inFrameset
            case .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title:
                push(headPointer)
                _ = inHead(&token)
                removeFromStack(headPointer)
            case .head: break
            default:
                insertFakeElement(.body, "body")
                framesetOK = true
                mode = .inBody
                return .reprocess
        }
        return .consumed
    }
}
