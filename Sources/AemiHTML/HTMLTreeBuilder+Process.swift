internal import AemiKernel

extension HTMLTreeBuilder {
    /// The tree construction dispatcher (13.2.6): a token goes to the rules of the insertion mode, or to those of foreign content.
    mutating func process(_ token: BuilderToken) {
        let skip = skipNewline
        skipNewline = false
        guard token.kind == .character else {
            var token = token
            dispatch(&token)
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
    func usesForeignRules(_ token: BuilderToken) -> Bool {
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
        if sawSelectedContent { document.updateSelectedContents() }
        document.declaredEncoding = declaredEncoding
    }
}
