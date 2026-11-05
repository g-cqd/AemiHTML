internal import AemiKernel

extension HTMLTreeBuilder {
    // MARK: after body (13.2.6.4.17)

    mutating func afterBody(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character where token.characterClass == .whitespace: return inBody(&token)
            case .comment:
                insertComment(token.text, at: Place(parent: stack.first ?? document.root, before: .none))
            case .processingInstruction:
                insertProcessingInstruction(token, at: Place(parent: stack.first ?? document.root, before: .none))
            case .doctype: break
            case .startTag where token.name == .html: return inBody(&token)
            case .endTag where token.name == .html:
                if contextElement.isNone { mode = .afterAfterBody }
            case .endOfFile: break
            default:
                mode = .inBody
                return .reprocess
        }
        return .consumed
    }

    // MARK: in frameset (13.2.6.4.18)

    mutating func inFrameset(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character where token.characterClass == .whitespace: insertCharacters(token.text)
            case .comment: insertComment(token.text)
            case .processingInstruction: insertProcessingInstruction(token)
            case .startTag where token.name == .html: return inBody(&token)
            case .startTag where token.name == .frameset: insertHTMLElement(token)
            case .endTag where token.name == .frameset:
                guard stack.count > 1 else { return .consumed }
                pop()
                if contextElement.isNone, !isHTML(currentNode, .frameset) { mode = .afterFrameset }
            case .startTag where token.name == .frame:
                insertHTMLElement(token)
                popJustInserted()
                acknowledge(&token)
            case .startTag where token.name == .noframes: return inHead(&token)
            default: break
        }
        return .consumed
    }

    // MARK: after frameset (13.2.6.4.19)

    mutating func afterFrameset(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .character where token.characterClass == .whitespace: insertCharacters(token.text)
            case .comment: insertComment(token.text)
            case .processingInstruction: insertProcessingInstruction(token)
            case .startTag where token.name == .html: return inBody(&token)
            case .endTag where token.name == .html: mode = .afterAfterFrameset
            case .startTag where token.name == .noframes: return inHead(&token)
            default: break
        }
        return .consumed
    }

    // MARK: after after body (13.2.6.4.20)

    mutating func afterAfterBody(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .comment: insertComment(token.text, at: Place(parent: document.root, before: .none))
            case .processingInstruction:
                insertProcessingInstruction(token, at: Place(parent: document.root, before: .none))
            case .doctype: return inBody(&token)
            case .character where token.characterClass == .whitespace: return inBody(&token)
            case .startTag where token.name == .html: return inBody(&token)
            case .endOfFile: break
            default:
                mode = .inBody
                return .reprocess
        }
        return .consumed
    }

    // MARK: after after frameset (13.2.6.4.21)

    mutating func afterAfterFrameset(_ token: inout BuilderToken) -> Disposition {
        switch token.kind {
            case .comment: insertComment(token.text, at: Place(parent: document.root, before: .none))
            case .processingInstruction:
                insertProcessingInstruction(token, at: Place(parent: document.root, before: .none))
            case .doctype: return inBody(&token)
            case .character where token.characterClass == .whitespace: return inBody(&token)
            case .startTag where token.name == .html: return inBody(&token)
            case .startTag where token.name == .noframes: return inHead(&token)
            default: break
        }
        return .consumed
    }
}
