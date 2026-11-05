internal import AemiKernel

extension HTMLTreeBuilder {
    var parsingTemplateContents: Bool {
        mutating get { hasTemplateOnStack || (!contextElement.isNone && isHTML(contextElement, .template)) }
    }

    // MARK: text (13.2.6.4.8)

    mutating func textMode(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character:
                insertCharacters(token.text)
            case .endOfFile:
                parseError(.unexpectedEndOfFile)
                pop()
                mode = originalMode
                return .reprocess
            default:
                // An end tag: `script` (nothing runs here) or any other; both pop the element.
                pop()
                mode = originalMode
        }
        return .consumed
    }

    // MARK: in table (13.2.6.4.9)

    mutating func inTable(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character where isHTML(currentNode, in: .tableTextContext):
                pendingTableText.removeAll(keepingCapacity: true)
                pendingTableTextHasNonWhitespace = false
                originalMode = mode
                mode = .inTableText
                return .reprocess
            case .comment:
                insertComment(token.text)
            case .processingInstruction:
                insertProcessingInstruction(token)
            case .doctype: parseError(.unexpectedDoctype)
            case .startTag: return inTableStartTag(&token)
            case .endTag: return inTableEndTag(&token)
            case .endOfFile: return inBody(&token)
            default: return inTableAnythingElse(&token)
        }
        return .consumed
    }

    mutating func inTableAnythingElse(_ token: inout BuilderToken) -> Disposition {
        if token.kind == .character { characterErrors(.fosterParenting, token) } else { parseError(.fosterParenting) }
        fosterParenting = true
        let result = inBody(&token)
        fosterParenting = false
        return result
    }

    mutating func clearStackBack(toContext stoppers: NameSet) {
        while let node = stack.last, !isHTML(node, in: stoppers) { pop() }
    }

    private mutating func inTableStartTag(_ token: inout BuilderToken) -> Disposition {
        switch token.name {
            case .caption:
                clearStackBack(toContext: .tableContext)
                insertMarker()
                insertHTMLElement(token)
                mode = .inCaption
            case .colgroup:
                clearStackBack(toContext: .tableContext)
                insertHTMLElement(token)
                mode = .inColumnGroup
            case .col:
                clearStackBack(toContext: .tableContext)
                insertFakeElement(.colgroup, "colgroup")
                mode = .inColumnGroup
                return .reprocess
            case .tbody, .tfoot, .thead:
                clearStackBack(toContext: .tableContext)
                insertHTMLElement(token)
                mode = .inTableBody
            case .td, .th, .tr:
                clearStackBack(toContext: .tableContext)
                insertFakeElement(.tbody, "tbody")
                mode = .inTableBody
                return .reprocess
            case .table:
                parseError(.nestedElement)
                guard hasInScope(.table, .table) else { return .consumed }
                popUntilHTML(.table)
                resetInsertionMode()
                return .reprocess
            case .style, .script, .template: return inHead(&token)
            case .input:
                guard let type = tokenAttribute(token, "type"), Self.equalsIgnoringCase(type, "hidden") else {
                    return inTableAnythingElse(&token)
                }
                parseError(.unexpectedStartTag)
                insertHTMLElement(token)
                popJustInserted()
                acknowledge(&token)
            case .form:
                parseError(.unexpectedStartTag)
                if !formPointer.isNone, !parsingTemplateContents { return .consumed }
                let node = insertHTMLElement(token)
                if !parsingTemplateContents { formPointer = node }
                popJustInserted()
            default: return inTableAnythingElse(&token)
        }
        return .consumed
    }

    private mutating func inTableEndTag(_ token: inout BuilderToken) -> Disposition {
        switch token.name {
            case .table:
                guard hasInScope(.table, .table) else {
                    parseError(.unexpectedEndTag)
                    return .consumed
                }
                popUntilHTML(.table)
                resetInsertionMode()
            case .body, .caption, .col, .colgroup, .html, .tbody, .td, .tfoot, .th, .thead, .tr:
                parseError(.unexpectedEndTag)
            case .template: return inHead(&token)
            default: return inTableAnythingElse(&token)
        }
        return .consumed
    }

    // MARK: in table text (13.2.6.4.10)

    mutating func inTableText(_ token: inout BuilderToken) -> Disposition {
        if token.kind == .character {
            switch token.characterClass {
                case .null: characterErrors(.unexpectedNullCharacter, token)
                case .whitespace: pendingTableText.append(token.text)
                case .other:
                    pendingTableText.append(token.text)
                    pendingTableTextHasNonWhitespace = true
            }
            return .consumed
        }
        if pendingTableTextHasNonWhitespace {
            // Each run is processed as the "anything else" of "in table" does: through "in body", with foster parenting.
            for range in pendingTableText {
                var run = BuilderToken(kind: .character, text: range)
                run.characterClass =
                    tokenizer.out.bytes(range: range).allSatisfy(Self.isWhitespace) ? .whitespace : .other
                _ = inTableAnythingElse(&run)
            }
        } else {
            for range in pendingTableText { insertCharacters(range) }
        }
        pendingTableText.removeAll(keepingCapacity: true)
        pendingTableTextHasNonWhitespace = false
        mode = originalMode
        return .reprocess
    }

    // MARK: in caption (13.2.6.4.11)

    mutating func inCaption(_ token: inout BuilderToken) -> Disposition {
        switch (token.kind, token.name) {
            case (.endTag, .caption):
                guard hasInScope(.caption, .table) else {
                    parseError(.unexpectedEndTag)
                    return .consumed
                }
                closeCaption()
                return .consumed
            case (.startTag, .caption), (.startTag, .col), (.startTag, .colgroup), (.startTag, .tbody),
                (.startTag, .td), (.startTag, .tfoot),
                (.startTag, .th), (.startTag, .thead), (.startTag, .tr), (.endTag, .table):
                guard hasInScope(.caption, .table) else {
                    tokenError(token)
                    return .consumed
                }
                closeCaption()
                return .reprocess
            case (.endTag, .body), (.endTag, .col), (.endTag, .colgroup), (.endTag, .html), (.endTag, .tbody),
                (.endTag, .td), (.endTag, .tfoot),
                (.endTag, .th), (.endTag, .thead), (.endTag, .tr):
                parseError(.unexpectedEndTag)
                return .consumed
            default: return inBody(&token)
        }
    }

    private mutating func closeCaption() {
        generateImpliedEndTags()
        expectCurrent(.caption)
        popUntilHTML(.caption)
        clearFormattingToMarker()
        mode = .inTable
    }

    // MARK: in column group (13.2.6.4.12)

    mutating func inColumnGroup(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character where token.characterClass == .whitespace:
                insertCharacters(token.text)
            case .comment:
                insertComment(token.text)
            case .processingInstruction:
                insertProcessingInstruction(token)
            case .doctype: parseError(.unexpectedDoctype)
            case .startTag where token.name == .html: return inBody(&token)
            case .startTag where token.name == .col:
                insertHTMLElement(token)
                popJustInserted()
                acknowledge(&token)
            case .endTag where token.name == .colgroup:
                guard isHTML(currentNode, .colgroup) else {
                    parseError(.unexpectedEndTag)
                    return .consumed
                }
                pop()
                mode = .inTable
            case .endTag where token.name == .col: parseError(.unexpectedEndTag)
            case .startTag where token.name == .template, .endTag where token.name == .template: return inHead(&token)
            case .endOfFile: return inBody(&token)
            default:
                guard isHTML(currentNode, .colgroup) else {
                    tokenError(token)
                    return .consumed
                }
                pop()
                mode = .inTable
                return .reprocess
        }
        return .consumed
    }

    // MARK: in table body (13.2.6.4.13)

    mutating func inTableBody(_ token: inout BuilderToken) -> Disposition {
        let stoppers = NameSet.tableBodyContext
        switch (token.kind, token.name) {
            case (.startTag, .tr):
                clearStackBack(toContext: stoppers)
                insertHTMLElement(token)
                mode = .inRow
            case (.startTag, .th), (.startTag, .td):
                parseError(.unexpectedStartTag)
                clearStackBack(toContext: stoppers)
                insertFakeElement(.tr, "tr")
                mode = .inRow
                return .reprocess
            case (.endTag, .tbody), (.endTag, .tfoot), (.endTag, .thead):
                guard hasInScope(token.name, .table) else {
                    parseError(.unexpectedEndTag)
                    return .consumed
                }
                clearStackBack(toContext: stoppers)
                pop()
                mode = .inTable
            case (.startTag, .caption), (.startTag, .col), (.startTag, .colgroup), (.startTag, .tbody),
                (.startTag, .tfoot), (.startTag, .thead),
                (.endTag, .table):
                guard hasInScope(.table, where: { $0 == .tbody || $0 == .thead || $0 == .tfoot }) else {
                    tokenError(token)
                    return .consumed
                }
                clearStackBack(toContext: stoppers)
                pop()
                mode = .inTable
                return .reprocess
            case (.endTag, .body), (.endTag, .caption), (.endTag, .col), (.endTag, .colgroup), (.endTag, .html),
                (.endTag, .td), (.endTag, .th),
                (.endTag, .tr):
                parseError(.unexpectedEndTag)
                return .consumed
            default: return inTable(&token)
        }
        return .consumed
    }

    // MARK: in row (13.2.6.4.14)

    mutating func inRow(_ token: inout BuilderToken) -> Disposition {
        switch (token.kind, token.name) {
            case (.startTag, .th), (.startTag, .td):
                clearStackBack(toContext: .tableRowContext)
                insertHTMLElement(token)
                mode = .inCell
                insertMarker()
            case (.endTag, .tr):
                guard hasInScope(.tr, .table) else {
                    parseError(.unexpectedEndTag)
                    return .consumed
                }
                clearStackBack(toContext: .tableRowContext)
                pop()
                mode = .inTableBody
            case (.startTag, .caption), (.startTag, .col), (.startTag, .colgroup), (.startTag, .tbody),
                (.startTag, .tfoot), (.startTag, .thead),
                (.startTag, .tr), (.endTag, .table):
                guard hasInScope(.tr, .table) else {
                    tokenError(token)
                    return .consumed
                }
                clearStackBack(toContext: .tableRowContext)
                pop()
                mode = .inTableBody
                return .reprocess
            case (.endTag, .tbody), (.endTag, .tfoot), (.endTag, .thead):
                guard hasInScope(token.name, .table), hasInScope(.tr, .table) else {
                    parseError(.unexpectedEndTag)
                    return .consumed
                }
                clearStackBack(toContext: .tableRowContext)
                pop()
                mode = .inTableBody
                return .reprocess
            case (.endTag, .body), (.endTag, .caption), (.endTag, .col), (.endTag, .colgroup), (.endTag, .html),
                (.endTag, .td), (.endTag, .th):
                parseError(.unexpectedEndTag)
                return .consumed
            default: return inTable(&token)
        }
        return .consumed
    }

    // MARK: in cell (13.2.6.4.15)

    mutating func inCell(_ token: inout BuilderToken) -> Disposition {
        switch (token.kind, token.name) {
            case (.endTag, .td), (.endTag, .th):
                guard hasInScope(token.name, .table) else {
                    parseError(.unexpectedEndTag)
                    return .consumed
                }
                closeCell()
            case (.startTag, .caption), (.startTag, .col), (.startTag, .colgroup), (.startTag, .tbody),
                (.startTag, .td), (.startTag, .tfoot),
                (.startTag, .th), (.startTag, .thead), (.startTag, .tr):
                guard hasInScope(.td, .table) || hasInScope(.th, .table) else {
                    parseError(.unexpectedStartTag)
                    return .consumed
                }
                closeCell()
                return .reprocess
            case (.endTag, .body), (.endTag, .caption), (.endTag, .col), (.endTag, .colgroup), (.endTag, .html):
                parseError(.unexpectedEndTag)
            case (.endTag, .table), (.endTag, .tbody), (.endTag, .tfoot), (.endTag, .thead), (.endTag, .tr):
                guard hasInScope(token.name, .table) else {
                    parseError(.unexpectedEndTag)
                    return .consumed
                }
                closeCell()
                return .reprocess
            default: return inBody(&token)
        }
        return .consumed
    }

    private mutating func closeCell() {
        generateImpliedEndTags()
        expectCurrentCell()
        popUntilHTML(in: .cells)
        clearFormattingToMarker()
        mode = .inRow
    }

    // MARK: in template (13.2.6.4.16)

    mutating func inTemplate(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character, .comment, .processingInstruction, .doctype: return inBody(&token)
            case .startTag:
                switch token.name {
                    case .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title:
                        return inHead(&token)
                    case .caption, .colgroup, .tbody, .tfoot, .thead: switchTemplateMode(.inTable)
                    case .col: switchTemplateMode(.inColumnGroup)
                    case .tr: switchTemplateMode(.inTableBody)
                    case .td, .th: switchTemplateMode(.inRow)
                    default: switchTemplateMode(.inBody)
                }
                return .reprocess
            case .endTag:
                if token.name == .template { return inHead(&token) }
                parseError(.unexpectedEndTag)
                return .consumed
            case .endOfFile:
                guard hasTemplateOnStack else { return .consumed }
                parseError(.unexpectedEndOfFile)
                popUntilHTML(.template)
                clearFormattingToMarker()
                templateModes.removeLast()
                resetInsertionMode()
                return .reprocess
        }
    }

    private mutating func switchTemplateMode(_ new: InsertionMode) {
        if !templateModes.isEmpty { templateModes.removeLast() }
        templateModes.append(new)
        mode = new
    }
}
