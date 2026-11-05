internal import AemiKernel

extension HTMLTreeBuilder {
    // MARK: in body (13.2.6.4.7)

    mutating func inBody(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character:
                switch token.characterClass {
                    case .null: characterErrors(.unexpectedNullCharacter, token)
                    case .whitespace:
                        reconstructFormatting()
                        insertCharacters(token.text)
                    case .other:
                        reconstructFormatting()
                        insertCharacters(token.text)
                        framesetOK = false
                }
            case .comment: insertComment(token.text)
            case .processingInstruction: insertProcessingInstruction(token)
            case .doctype: parseError(.unexpectedDoctype)
            case .startTag: return inBodyStartTag(&token)
            case .endTag: return inBodyEndTag(&token)
            case .endOfFile:
                if !templateModes.isEmpty { return inTemplate(&token) }
                if collectsErrors, hasNodeNotAllowedAtEnd() { parseError(.unexpectedEndOfFile) }
        }
        return .consumed
    }

    /// Adds the token's attributes that the element does not have (the `html` and `body` start tags that arrive late).
    mutating func addMissingAttributes(to node: Node, from token: BuilderToken) {
        for number in 0 ..< attributeCount(token) {
            let at = token.index + 2 + number * 2
            let nameSlot = tokenizer.out.tape[at]
            let valueSlot = tokenizer.out.tape[at + 1]
            let name = TapeSlot.make(tag: 0, aux: TapeSlot.aux(nameSlot), low: TapeSlot.low(nameSlot))
            if !hasAttribute(node, tokenizer.out.bytes(range: name)) {
                document.addAttribute(
                    node,
                    name: name,
                    value: TapeSlot.make(tag: 0, aux: TapeSlot.aux(valueSlot), low: TapeSlot.low(valueSlot))
                )
            }
        }
    }

    /// Whether the stack holds an element the end of the input (or `</body>`, `</html>`) may not leave open: anything but `dd dt li optgroup option p rb rp rt rtc tbody td tfoot th thead tr body html`.
    mutating func hasNodeNotAllowedAtEnd() -> Bool {
        for node in stack where !(isHTMLElement(node) && Self.mayStayOpen(name(of: node))) { return true }
        return false
    }

    private static func mayStayOpen(_ name: HTMLName) -> Bool {
        switch name {
            case .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc, .tbody, .td, .tfoot, .th, .thead, .tr,
                .body,
                .html:
                true
            default: false
        }
    }

    private var hasParagraphInButtonScope: Bool { mutating get { hasInScope(.p, .button) } }

    private mutating func isFragmentSelect() -> Bool { !contextElement.isNone && isHTML(contextElement, .select) }

    // MARK: Start tags

    private mutating func inBodyStartTag(_ token: inout BuilderToken) -> Disposition {
        switch token.name {
            case .html:
                parseError(.unexpectedStartTag)
                if !hasTemplateOnStack, let root = stack.first { addMissingAttributes(to: root, from: token) }
            case .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title:
                return inHead(&token)
            case .body:
                parseError(.unexpectedStartTag)
                guard stack.count > 1, isHTML(stack[1], .body), !hasTemplateOnStack else { return .consumed }
                framesetOK = false
                addMissingAttributes(to: stack[1], from: token)
            case .frameset:
                parseError(.unexpectedStartTag)
                guard stack.count > 1, isHTML(stack[1], .body), framesetOK else { return .consumed }
                document.detach(stack[1])
                stack.removeSubrange(1...)
                insertHTMLElement(token)
                mode = .inFrameset
            case .address, .article, .aside, .blockquote, .center, .details, .dialog, .dir, .div, .dl, .fieldset,
                .figcaption, .figure, .footer, .header,
                .hgroup, .main, .menu, .nav, .ol, .p, .search, .section, .summary, .ul:
                if hasParagraphInButtonScope { closeP() }
                insertHTMLElement(token)
            case .h1, .h2, .h3, .h4, .h5, .h6:
                if hasParagraphInButtonScope { closeP() }
                if isHTMLElement(currentNode), Self.isHeading(name(of: currentNode)) {
                    parseError(.nestedElement)
                    pop()
                }
                insertHTMLElement(token)
            case .pre, .listing:
                if hasParagraphInButtonScope { closeP() }
                insertHTMLElement(token)
                skipNewline = true
                framesetOK = false
            case .form:
                if !formPointer.isNone, !parsingTemplateContents {
                    parseError(.nestedElement)
                    return .consumed
                }
                if hasParagraphInButtonScope { closeP() }
                let node = insertHTMLElement(token)
                if !parsingTemplateContents { formPointer = node }
            case .li: listItemStart(token, items: .listItems)
            case .dd, .dt: listItemStart(token, items: .definitionItems)
            case .plaintext:
                if hasParagraphInButtonScope { closeP() }
                insertHTMLElement(token)
                tokenizer.switchTo(.plaintext)
            case .button:
                if hasInScope(.button) {
                    parseError(.nestedElement)
                    generateImpliedEndTags()
                    popUntilHTML(.button)
                }
                reconstructFormatting()
                insertHTMLElement(token)
                framesetOK = false
            default: return inBodyStartTagFormatting(&token)
        }
        return .consumed
    }

    /// The `li`, `dd` and `dt` start tags: close the open item of the same kind, up to the nearest special element that is not `address`, `div` or `p`.
    private mutating func listItemStart(_ token: BuilderToken, items: NameSet) {
        framesetOK = false
        var index = stack.count - 1
        while index >= 0 {
            let node = stack[index]
            if isHTML(node, in: items) {
                let found = name(of: node)
                generateImpliedEndTags(except: found)
                expectCurrent(found)
                popUntilHTML(found)
                break
            }
            if isSpecial(node), !isHTML(node, .address, .div, .p) { break }
            index -= 1
        }
        if hasParagraphInButtonScope { closeP() }
        insertHTMLElement(token)
    }

    private mutating func inBodyStartTagFormatting(_ token: inout BuilderToken) -> Disposition {
        switch token.name {
            case .a:
                if let position = formatting.lastIndex(where: { $0.isMarker }).map({ $0 + 1 }) ?? 0 as Int?,
                    let existing = formatting[position...].last(where: { !$0.isMarker && isHTML($0.node, .a) })
                {
                    parseError(.nestedElement)
                    adoptionAgency(.a, token: token)
                    if let at = formattingIndex(of: existing.node) { formatting.remove(at: at) }
                    removeFromStack(existing.node)
                }
                reconstructFormatting()
                let node = insertHTMLElement(token)
                pushFormatting(node, tokenIndex: token.index)
            case .b, .big, .code, .em, .font, .i, .s, .small, .strike, .strong, .tt, .u:
                reconstructFormatting()
                let node = insertHTMLElement(token)
                pushFormatting(node, tokenIndex: token.index)
            case .nobr:
                reconstructFormatting()
                if hasInScope(.nobr) {
                    parseError(.nestedElement)
                    adoptionAgency(.nobr, token: token)
                    reconstructFormatting()
                }
                let node = insertHTMLElement(token)
                pushFormatting(node, tokenIndex: token.index)
            case .applet, .marquee, .object:
                reconstructFormatting()
                insertHTMLElement(token)
                insertMarker()
                framesetOK = false
            case .table:
                if document.quirksMode != .quirks, hasParagraphInButtonScope { closeP() }
                insertHTMLElement(token)
                framesetOK = false
                mode = .inTable
            default: return inBodyStartTagVoid(&token)
        }
        return .consumed
    }

    private mutating func inBodyStartTagVoid(_ token: inout BuilderToken) -> Disposition {
        switch token.name {
            case .area, .br, .embed, .img, .keygen, .wbr:
                reconstructFormatting()
                insertHTMLElement(token)
                popJustInserted()
                acknowledge(&token)
                framesetOK = false
            case .input:
                if isFragmentSelect() {
                    parseError(.unexpectedStartTag)
                    return .consumed
                }
                if hasInScope(.select) {
                    parseError(.unexpectedStartTag)
                    popUntilHTML(.select)
                }
                reconstructFormatting()
                insertHTMLElement(token)
                popJustInserted()
                acknowledge(&token)
                if let type = tokenAttribute(token, "type"), Self.equalsIgnoringCase(type, "hidden") {
                } else {
                    framesetOK = false
                }
            case .param, .source, .track:
                insertHTMLElement(token)
                popJustInserted()
                acknowledge(&token)
            case .hr:
                if hasParagraphInButtonScope { closeP() }
                if hasInScope(.select) {
                    generateImpliedEndTags()
                    if collectsErrors, hasInScope(.option) || hasInScope(.optgroup) { parseError(.unexpectedStartTag) }
                }
                insertHTMLElement(token)
                popJustInserted()
                acknowledge(&token)
                framesetOK = false
            case .image:
                parseError(.imageStartTag)
                token.name = .img
                nameOverride = (.img, "img")
                return inBody(&token)
            default: return inBodyStartTagRaw(&token)
        }
        return .consumed
    }

    private mutating func inBodyStartTagRaw(_ token: inout BuilderToken) -> Disposition {
        switch token.name {
            case .textarea:
                insertHTMLElement(token)
                skipNewline = true
                tokenizer.switchTo(.rcdata)
                originalMode = mode
                framesetOK = false
                mode = .text
            case .xmp:
                if hasParagraphInButtonScope { closeP() }
                reconstructFormatting()
                framesetOK = false
                parseRawText(token, rcdata: false)
            case .iframe:
                framesetOK = false
                parseRawText(token, rcdata: false)
            case .noembed: parseRawText(token, rcdata: false)
            case .noscript where scripting: parseRawText(token, rcdata: false)
            case .select:
                if isFragmentSelect() {
                    parseError(.unexpectedStartTag)
                    return .consumed
                }
                if hasInScope(.select) {
                    parseError(.nestedElement)
                    popUntilHTML(.select)
                    return .consumed
                }
                reconstructFormatting()
                insertHTMLElement(token)
                framesetOK = false
            case .option:
                if hasInScope(.select) {
                    generateImpliedEndTags(except: .optgroup)
                    if collectsErrors, hasInScope(.option) { parseError(.unexpectedStartTag) }
                } else if isHTML(currentNode, .option) {
                    pop()
                }
                reconstructFormatting()
                insertHTMLElement(token)
            case .optgroup:
                if hasInScope(.select) {
                    generateImpliedEndTags()
                    if collectsErrors, hasInScope(.option) || hasInScope(.optgroup) { parseError(.unexpectedStartTag) }
                } else if isHTML(currentNode, .option) {
                    pop()
                }
                reconstructFormatting()
                insertHTMLElement(token)
            case .rb, .rtc:
                if hasInScope(.ruby) { generateImpliedEndTags() }
                expectCurrent(.ruby)
                insertHTMLElement(token)
            case .rp, .rt:
                if hasInScope(.ruby) { generateImpliedEndTags(except: .rtc) }
                if collectsErrors, !isHTML(currentNode, .rtc), !isHTML(currentNode, .ruby) {
                    parseError(.unclosedElement)
                }
                insertHTMLElement(token)
            case .math, .svg:
                reconstructFormatting()
                let isSVG = token.name == .svg
                insertForeignElement(tokenIndex: token.index, space: isSVG ? .svg : .mathml)
                if token.selfClosing {
                    popJustInserted()
                    acknowledge(&token)
                }
            case .caption, .col, .colgroup, .frame, .head, .tbody, .td, .tfoot, .th, .thead, .tr:
                parseError(.unexpectedStartTag)
            default:
                reconstructFormatting()
                insertHTMLElement(token)
        }
        return .consumed
    }

    // MARK: End tags

    private mutating func inBodyEndTag(_ token: inout BuilderToken) -> Disposition {
        switch token.name {
            case .template: return inHead(&token)
            case .body:
                guard hasInScope(.body) else {
                    parseError(.unexpectedEndTag)
                    return .consumed
                }
                if collectsErrors, hasNodeNotAllowedAtEnd() { parseError(.unclosedElement) }
                mode = .afterBody
            case .html:
                guard hasInScope(.body) else {
                    parseError(.unexpectedEndTag)
                    return .consumed
                }
                if collectsErrors, hasNodeNotAllowedAtEnd() { parseError(.unclosedElement) }
                mode = .afterBody
                return .reprocess
            case .address, .article, .aside, .blockquote, .button, .center, .details, .dialog, .dir, .div, .dl,
                .fieldset, .figcaption, .figure, .footer,
                .header, .hgroup, .listing, .main, .menu, .nav, .ol, .pre, .search, .section, .select, .summary, .ul:
                closeScoped(token.name)
            case .form: closeForm()
            case .p:
                if !hasParagraphInButtonScope {
                    parseError(.unexpectedEndTag)
                    insertFakeElement(.p, "p")
                }
                closeP()
            case .li:
                closeScoped(.li, scope: .listItem, keeping: .li)
            case .dd, .dt:
                closeScoped(token.name, keeping: token.name)
            case .h1, .h2, .h3, .h4, .h5, .h6:
                guard hasInScope(.regular, where: Self.isHeading) else {
                    parseError(.unexpectedEndTag)
                    return .consumed
                }
                generateImpliedEndTags()
                expectCurrent(token.name)
                popUntilHeading()
            case .a, .b, .big, .code, .em, .font, .i, .nobr, .s, .small, .strike, .strong, .tt, .u:
                adoptionAgency(token.name, token: token)
            case .applet, .marquee, .object:
                if closeScoped(token.name) { clearFormattingToMarker() }
            case .br:
                parseError(.unexpectedEndTag)
                reconstructFormatting()
                insertFakeElement(.br, "br")
                popJustInserted()
                framesetOK = false
            default: anyOtherEndTag(token)
        }
        return .consumed
    }

    /// The end tag of an element that must be in scope (13.2.6.4.7): without it the tag is a parse error and is ignored; with it, the implied end tags (`keeping` the one that is not implied here) are generated, an element left open is an error, and the stack is popped through the element. Whether the element was in scope.
    @discardableResult
    private mutating func closeScoped(_ name: HTMLName, scope: Scope = .regular, keeping kept: HTMLName = .unknown)
        -> Bool
    {
        guard hasInScope(name, scope) else {
            parseError(.unexpectedEndTag)
            return false
        }
        generateImpliedEndTags(except: kept)
        expectCurrent(name)
        popUntilHTML(name)
        return true
    }

    private mutating func closeForm() {
        if !parsingTemplateContents {
            let node = formPointer
            formPointer = .none
            guard !node.isNone, hasInScope(node) else {
                parseError(.unexpectedEndTag)
                return
            }
            generateImpliedEndTags()
            if collectsErrors, currentNode != node { parseError(.unclosedElement) }
            removeFromStack(node)
        } else {
            guard hasInScope(.form) else {
                parseError(.unexpectedEndTag)
                return
            }
            generateImpliedEndTags()
            expectCurrent(.form)
            popUntilHTML(.form)
        }
    }

    /// 13.2.6.4.7 "any other end tag": closes the nearest open element of that name unless a special element is in the way.
    mutating func anyOtherEndTag(_ token: BuilderToken) {
        let bytes = tagNameBytes(token)
        var index = stack.count - 1
        while index >= 0 {
            let node = stack[index]
            if isHTMLElement(node), token.name == name(of: node),
                token.name != .unknown || nameBytes(of: node).elementsEqual(bytes)
            {
                generateImpliedEndTags(except: token.name == .unknown ? .unknown : token.name)
                if collectsErrors, stack.count - 1 != index { parseError(.unclosedElement) }
                while stack.count > index { pop() }
                return
            }
            if isSpecial(node) {
                parseError(.unexpectedEndTag)
                return
            }
            index -= 1
        }
    }
}
