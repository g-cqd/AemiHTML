internal import AemiKernel

extension HTMLTreeBuilder {
    mutating func isMathMLTextIntegrationPoint(_ node: Node) -> Bool {
        guard space(of: node) == .mathml else { return false }
        switch name(of: node) {
            case .mi, .mo, .mn, .ms, .mtext: return true
            default: return false
        }
    }

    mutating func isHTMLIntegrationPoint(_ node: Node) -> Bool {
        switch space(of: node) {
            case .html: return false
            case .mathml: return name(of: node) == .annotationXml && htmlIntegrationAnnotations.contains(node.raw)
            case .svg:
                switch name(of: node) {
                    case .foreignObject, .desc, .title: return true
                    default: return false
                }
        }
    }

    /// 13.2.6.5: the rules for parsing tokens in foreign content.
    mutating func foreignContent(_ token: inout BuilderToken) {
        switch token.kind {
            case .character:
                switch token.characterClass {
                    case .null:
                        let replacement = tokenizer.out.intern([0xEF, 0xBF, 0xBD])
                        for _ in 0 ..< length(token.text) { insertCharacters(replacement) }
                    case .whitespace: insertCharacters(token.text)
                    case .other:
                        insertCharacters(token.text)
                        framesetOK = false
                }
            case .comment: insertComment(token.text)
            case .processingInstruction: insertProcessingInstruction(token)
            case .doctype, .endOfFile: break
            case .startTag: foreignStartTag(&token)
            case .endTag: foreignEndTag(&token)
        }
    }

    private mutating func breaksOut(_ token: BuilderToken) -> Bool {
        switch token.name {
            case .b, .big, .blockquote, .body, .br, .center, .code, .dd, .div, .dl, .dt, .em, .embed, .h1, .h2, .h3,
                .h4, .h5, .h6, .head, .hr, .i, .img,
                .li, .listing, .menu, .meta, .nobr, .ol, .p, .pre, .ruby, .s, .small, .span, .strong, .strike, .sub,
                .sup, .table, .tt, .u, .ul, .var_:
                return true
            case .font:
                return tokenHasAttribute(token, "color") || tokenHasAttribute(token, "face")
                    || tokenHasAttribute(token, "size")
            default: return false
        }
    }

    private mutating func popToHTMLContent() {
        while let node = stack.last, !isMathMLTextIntegrationPoint(node), !isHTMLIntegrationPoint(node),
            !isHTMLElement(node)
        { pop() }
    }

    private mutating func foreignStartTag(_ token: inout BuilderToken) {
        if breaksOut(token) {
            popToHTMLContent()
            var again = token
            while handle(&again) == .reprocess {}
            return
        }
        let adjusted = adjustedCurrentNode
        let space = space(of: adjusted)
        _ = insertForeignElement(tokenIndex: token.index, space: space)
        if token.selfClosing {
            acknowledge(&token)
            // An SVG `script` acts as its own end tag; every other element is popped.
            popJustInserted()
        }
    }

    private mutating func foreignEndTag(_ token: inout BuilderToken) {
        if token.name == .br || token.name == .p {
            popToHTMLContent()
            var again = token
            while handle(&again) == .reprocess {}
            return
        }
        if token.name == .script, isElement(currentNode, .script, in: .svg) {
            pop()
            return
        }
        let wanted = tagNameBytes(token)
        var index = stack.count - 1
        while index >= 0 {
            let node = stack[index]
            if index == 0 { return }
            if Self.equalsLowered(nameBytes(of: node), wanted) {
                while stack.count > index { pop() }
                return
            }
            index -= 1
            if isHTMLElement(stack[index]) {
                var again = token
                while handle(&again) == .reprocess {}
                return
            }
        }
    }
}
