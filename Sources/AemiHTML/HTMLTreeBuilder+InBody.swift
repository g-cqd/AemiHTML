internal import AemiKernel

extension HTMLTreeBuilder {
    // MARK: in body (13.2.6.4.7)

    mutating func inBody(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character:
                switch token.characterClass {
                    case .null: break
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
            case .doctype: break
            case .startTag: return inBodyStartTag(&token)
            case .endTag: return inBodyEndTag(&token)
            case .endOfFile:
                if !templateModes.isEmpty { return inTemplate(&token) }
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

    private var hasParagraphInButtonScope: Bool { mutating get { hasInScope(.p, .button) } }

    private mutating func isFragmentSelect() -> Bool { !contextElement.isNone && isHTML(contextElement, .select) }

    // MARK: Start tags

    private mutating func inBodyStartTag(_ token: inout BuilderToken) -> Disposition {
        switch token.name {
            case .html:
                if !hasTemplateOnStack, let root = stack.first { addMissingAttributes(to: root, from: token) }
            case .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title:
                return inHead(&token)
            case .body:
                guard stack.count > 1, isHTML(stack[1], .body), !hasTemplateOnStack else { return .consumed }
                framesetOK = false
                addMissingAttributes(to: stack[1], from: token)
            case .frameset:
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
                if isHTMLElement(currentNode), Self.isHeading(name(of: currentNode)) { pop() }
                insertHTMLElement(token)
            case .pre, .listing:
                if hasParagraphInButtonScope { closeP() }
                insertHTMLElement(token)
                skipNewline = true
                framesetOK = false
            case .form:
                if !formPointer.isNone, !parsingTemplateContents { return .consumed }
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
                if isFragmentSelect() { return .consumed }
                if hasInScope(.select) { popUntilHTML(.select) }
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
                if hasInScope(.select) { generateImpliedEndTags() }
                insertHTMLElement(token)
                popJustInserted()
                acknowledge(&token)
                framesetOK = false
            case .image:
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
                if isFragmentSelect() { return .consumed }
                if hasInScope(.select) {
                    popUntilHTML(.select)
                    return .consumed
                }
                reconstructFormatting()
                insertHTMLElement(token)
                framesetOK = false
            case .option:
                if hasInScope(.select) {
                    generateImpliedEndTags(except: .optgroup)
                } else if isHTML(currentNode, .option) {
                    pop()
                }
                reconstructFormatting()
                insertHTMLElement(token)
            case .optgroup:
                if hasInScope(.select) { generateImpliedEndTags() } else if isHTML(currentNode, .option) { pop() }
                reconstructFormatting()
                insertHTMLElement(token)
            case .rb, .rtc:
                if hasInScope(.ruby) { generateImpliedEndTags() }
                insertHTMLElement(token)
            case .rp, .rt:
                if hasInScope(.ruby) { generateImpliedEndTags(except: .rtc) }
                insertHTMLElement(token)
            case .math, .svg:
                reconstructFormatting()
                let isSVG = token.name == .svg
                insertForeignElement(tokenIndex: token.index, space: isSVG ? .svg : .mathml)
                if token.selfClosing {
                    popJustInserted()
                    acknowledge(&token)
                }
            case .caption, .col, .colgroup, .frame, .head, .tbody, .td, .tfoot, .th, .thead, .tr: break
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
                guard hasInScope(.body) else { return .consumed }
                mode = .afterBody
            case .html:
                guard hasInScope(.body) else { return .consumed }
                mode = .afterBody
                return .reprocess
            case .address, .article, .aside, .blockquote, .button, .center, .details, .dialog, .dir, .div, .dl,
                .fieldset, .figcaption, .figure, .footer,
                .header, .hgroup, .listing, .main, .menu, .nav, .ol, .pre, .search, .section, .select, .summary, .ul:
                let name = token.name
                guard hasInScope(name) else { return .consumed }
                generateImpliedEndTags()
                popUntilHTML(name)
            case .form: closeForm()
            case .p:
                if !hasParagraphInButtonScope { insertFakeElement(.p, "p") }
                closeP()
            case .li:
                guard hasInScope(.li, .listItem) else { return .consumed }
                generateImpliedEndTags(except: .li)
                popUntilHTML(.li)
            case .dd, .dt:
                let name = token.name
                guard hasInScope(name) else { return .consumed }
                generateImpliedEndTags(except: name)
                popUntilHTML(name)
            case .h1, .h2, .h3, .h4, .h5, .h6:
                guard hasInScope(.regular, where: Self.isHeading) else { return .consumed }
                generateImpliedEndTags()
                popUntilHeading()
            case .a, .b, .big, .code, .em, .font, .i, .nobr, .s, .small, .strike, .strong, .tt, .u:
                adoptionAgency(token.name, token: token)
            case .applet, .marquee, .object:
                let name = token.name
                guard hasInScope(name) else { return .consumed }
                generateImpliedEndTags()
                popUntilHTML(name)
                clearFormattingToMarker()
            case .br:
                reconstructFormatting()
                insertFakeElement(.br, "br")
                popJustInserted()
                framesetOK = false
            default: anyOtherEndTag(token)
        }
        return .consumed
    }

    private mutating func closeForm() {
        if !parsingTemplateContents {
            let node = formPointer
            formPointer = .none
            guard !node.isNone, hasInScope(node) else { return }
            generateImpliedEndTags()
            removeFromStack(node)
        } else {
            guard hasInScope(.form) else { return }
            generateImpliedEndTags()
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
                while stack.count > index { pop() }
                return
            }
            if isSpecial(node) { return }
            index -= 1
        }
    }
}
