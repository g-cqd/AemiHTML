internal import AemiKernel

extension HTMLTreeBuilder {
    /// The tree construction dispatcher (13.2.6): a token goes to the rules of the insertion mode, or to those of foreign content.
    mutating func process(_ token: BuilderToken) {
        let skip = skipNewline
        skipNewline = false
        if collectsErrors { errorOffset = sourceOffset(of: token) }
        guard token.kind == .character else {
            var token = token
            dispatch(&token)
            if collectsErrors, token.kind == .startTag, token.selfClosing, !token.acknowledged {
                codedErrors.append(
                    HTMLTokens.Error(
                        code: .nonVoidHtmlElementStartTagWithTrailingSolidus,
                        offset: Swift.max(errorOffset, 0)
                    )
                )
            }
            return
        }
        var from = 0
        let total = length(token.text)
        let bytes = tokenizer.out.bytes(range: token.text)
        let base = bytes.startIndex
        if skip, total > 0, bytes[base] == 0x0A { from = 1 }
        while from < total {
            let first = bytes[base + from]
            let kind: CharacterClass = first == 0 ? .null : (Self.isWhitespace(first) ? .whitespace : .other)
            var end = from + 1
            while end < total {
                let next = bytes[base + end]
                let nextKind: CharacterClass = next == 0 ? .null : (Self.isWhitespace(next) ? .whitespace : .other)
                if nextKind != kind { break }
                end += 1
            }
            var run = BuilderToken(kind: .character, text: sub(token.text, from, end))
            run.characterClass = kind
            dispatch(&run)
            from = end
        }
    }

    mutating func dispatch(_ token: inout BuilderToken) {
        while true {
            if usesForeignRules(token) {
                foreignContent(&token)
                return
            }
            if handle(&token) == .consumed { return }
        }
    }

    /// Whether the token goes to the rules for foreign content (the list of 13.2.6).
    mutating func usesForeignRules(_ token: BuilderToken) -> Bool {
        // The common case first: the adjusted current node is an HTML element.
        let node = (stack.count == 1 && !contextElement.isNone) ? contextElement : (stack.last ?? .none)
        if node.isNone || document.namespaceRaw(node) == HTMLDocument.Namespace.html.rawValue
            || token.kind == .endOfFile
        {
            return false
        }
        switch space(of: node) {
            case .html: return false
            case .mathml:
                let current = name(of: node)
                if current == .mi || current == .mo || current == .mn || current == .ms || current == .mtext {
                    if token.kind == .startTag, token.name != .mglyph, token.name != .malignmark { return false }
                    if token.kind == .character { return false }
                }
                if current == .annotationXml, token.kind == .startTag, token.name == .svg { return false }
                if htmlIntegrationAnnotations.contains(node.raw), token.kind == .startTag || token.kind == .character {
                    return false
                }
                return true
            case .svg:
                let current = name(of: node)
                if current == .foreignObject || current == .desc || current == .title,
                    token.kind == .startTag || token.kind == .character
                {
                    return false
                }
                return true
        }
    }

    mutating func handle(_ token: inout BuilderToken) -> Disposition {
        switch mode {
            case .initial: initial(&token)
            case .beforeHTML: beforeHTML(&token)
            case .beforeHead: beforeHead(&token)
            case .inHead: inHead(&token)
            case .inHeadNoscript: inHeadNoscript(&token)
            case .afterHead: afterHead(&token)
            case .inBody: inBody(&token)
            case .text: textMode(&token)
            case .inTable: inTable(&token)
            case .inTableText: inTableText(&token)
            case .inCaption: inCaption(&token)
            case .inColumnGroup: inColumnGroup(&token)
            case .inTableBody: inTableBody(&token)
            case .inRow: inRow(&token)
            case .inCell: inCell(&token)
            case .inTemplate: inTemplate(&token)
            case .afterBody: afterBody(&token)
            case .inFrameset: inFrameset(&token)
            case .afterFrameset: afterFrameset(&token)
            case .afterAfterBody: afterAfterBody(&token)
            case .afterAfterFrameset: afterAfterFrameset(&token)
        }
    }

    // MARK: Parse errors

    /// Notes a parse error of class `kind` at the token being processed. Nothing is kept unless errors were asked for.
    @inline(__always)
    mutating func parseError(_ kind: HTMLTreeError) {
        if _slowPath(collectsErrors) { record(kind) }
    }

    /// "If the current node is not `name`, this is a parse error" (`unclosedElement`). The check is out of line: it runs only when errors are collected.
    @inline(__always)
    mutating func expectCurrent(_ name: HTMLName) {
        if _slowPath(collectsErrors) { checkCurrent(name) }
    }

    /// As `expectCurrent`, for the two names a table cell may end on.
    @inline(__always)
    mutating func expectCurrentCell() {
        if _slowPath(collectsErrors) { checkCurrentCell() }
    }

    @inline(never)
    private mutating func checkCurrent(_ name: HTMLName) {
        if !isHTML(currentNode, name) { record(.unclosedElement) }
    }

    @inline(never)
    private mutating func checkCurrentCell() {
        if !isHTML(currentNode, .td), !isHTML(currentNode, .th) { record(.unclosedElement) }
    }

    /// The part that keeps the error: not inlined, so the hundred places that may report one stay small.
    @inline(never)
    private mutating func record(_ kind: HTMLTreeError) {
        document.treeErrors.append(HTMLDocument.TreeError(kind: kind, offset: errorOffset >= 0 ? errorOffset : nil))
    }

    /// One parse error of class `kind` for each character of a character token, at that character: the standard's character tokens are single characters, and each is an error of its own.
    mutating func characterErrors(_ kind: HTMLTreeError, _ token: BuilderToken, onlyFirst: Bool = false) {
        guard collectsErrors else { return }
        let slot = token.text
        let inSource = TapeSlot.aux(slot) & 1 == 0
        let start = TapeSlot.low(slot)
        let bytes = tokenizer.out.bytes(range: slot)
        var position = 0
        for byte in bytes {
            defer { position += 1 }
            // A continuation byte belongs to the character before it.
            if byte & 0xC0 == 0x80 { continue }
            document.treeErrors.append(HTMLDocument.TreeError(kind: kind, offset: inSource ? start + position : nil))
            if onlyFirst { return }
        }
    }

    /// The parse error of a token that the insertion mode's "anything else" rule calls one: by the kind of the token.
    ///
    /// A rule that hands the token to another insertion mode (`reprocess`) is an error for its first character only: the others are judged by the mode they arrive in. A rule that ignores the token
    /// is an error for each of its characters, which is `onlyFirst: false`.
    mutating func tokenError(_ token: BuilderToken, onlyFirst: Bool = false) {
        guard collectsErrors else { return }
        switch token.kind {
            case .character:
                characterErrors(
                    token.characterClass == .null ? .unexpectedNullCharacter : .unexpectedCharacter,
                    token,
                    onlyFirst: onlyFirst
                )
            case .startTag: parseError(.unexpectedStartTag)
            case .endTag: parseError(.unexpectedEndTag)
            case .doctype: parseError(.unexpectedDoctype)
            case .endOfFile: parseError(.unexpectedEndOfFile)
            case .comment, .processingInstruction: break
        }
    }

    /// Where the token's name or text starts in the source, if the tokenizer left it there (-1 for the end of the input and for text it made).
    private func sourceOffset(of token: BuilderToken) -> Int {
        let slot: UInt64
        switch token.kind {
            case .character, .comment: slot = token.text
            case .startTag, .endTag, .doctype, .processingInstruction: slot = tokenizer.out.tape[token.index + 1]
            case .endOfFile: return tokenizer.out.source.count
        }
        return TapeSlot.aux(slot) & 1 == 0 ? TapeSlot.low(slot) : -1
    }

    // MARK: Synthetic tokens

    /// An element for a start tag the standard invents (`html`, `head`, `body`, `p`, `tbody`...), with no attributes.
    @discardableResult
    mutating func insertFakeElement(_ name: HTMLName, _ spelling: String) -> Node {
        let range = tokenizer.out.intern(utf8: spelling)
        let node = document.makeNode(.element, name: name, space: .html, nameRange: range)
        if name == .template { document.append(document.makeNode(.templateContents), to: node) }
        insertNode(node, at: appropriatePlace())
        if stack.count < maxDepth {
            push(node)
            lastInsertWasLeaf = false
        } else {
            lastInsertWasLeaf = true
        }
        return node
    }

    /// Acknowledges a self-closing flag (the builder does not report the parse error for one it did not).
    func acknowledge(_ token: inout BuilderToken) { token.acknowledged = true }

    // MARK: Finishing

    mutating func finish() {
        document.source = tokenizer.out.source
        document.scratch = tokenizer.out.scratch
        document.errors = tokenizer.out.errors
        if !codedErrors.isEmpty {
            document.errors.append(contentsOf: codedErrors)
            document.errors.sort { $0.offset < $1.offset }
        }
        if sawSelectedContent { document.updateSelectedContents() }
        document.declaredEncoding = declaredEncoding
    }
}

extension HTMLTreeBuilder {
    @inline(__always) func noError(_ kind: HTMLTreeError) {}
}
