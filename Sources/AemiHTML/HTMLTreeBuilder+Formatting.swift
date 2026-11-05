internal import AemiKernel

extension HTMLTreeBuilder {
    // MARK: The list of active formatting elements (13.2.4.3)

    func formattingIndex(of node: Node) -> Int? { formatting.lastIndex { $0.node == node } }

    /// Whether the start tags at two tape indices have the same attributes, as sets of names and values (the Noah's Ark comparison, on the tokens' attributes).
    func sameAttributes(_ a: Int, _ b: Int) -> Bool {
        let tape = tokenizer.out.tape
        let count = Int(TapeSlot.aux(tape[a]) & 0xFFF)
        guard count == Int(TapeSlot.aux(tape[b]) & 0xFFF) else { return false }
        for first in 0 ..< count {
            let name = tokenizer.out.bytes(ofSlot: a + 2 + first * 2)
            var found = false
            for second in 0 ..< count where tokenizer.out.bytes(ofSlot: b + 2 + second * 2).elementsEqual(name) {
                found = tokenizer.out.bytes(ofSlot: a + 3 + first * 2)
                    .elementsEqual(tokenizer.out.bytes(ofSlot: b + 3 + second * 2))
                break
            }
            if !found { return false }
        }
        return true
    }

    /// Pushes onto the list of active formatting elements, dropping the earliest of three equal entries after the last marker (the Noah's Ark clause).
    mutating func pushFormatting(_ node: Node, tokenIndex: Int) {
        var matches: [Int] = []
        var index = formatting.count - 1
        while index >= 0, !formatting[index].isMarker {
            let entry = formatting[index]
            if document.names[Int(entry.node.raw)] == document.names[Int(node.raw)],
                document.namespaces[Int(entry.node.raw)] == document.namespaces[Int(node.raw)],
                sameAttributes(entry.tokenIndex, tokenIndex)
            {
                matches.append(index)
            }
            index -= 1
        }
        if matches.count >= 3, let earliest = matches.last { formatting.remove(at: earliest) }
        formatting.append(FormattingEntry(node: node, tokenIndex: tokenIndex))
    }

    mutating func insertMarker() { formatting.append(FormattingEntry(node: .none, tokenIndex: 0)) }

    mutating func clearFormattingToMarker() {
        while let entry = formatting.popLast() {
            if entry.isMarker { return }
        }
    }

    /// 13.2.4.3: reopens the formatting elements that were open when the current context began and are not on the stack.
    mutating func reconstructFormatting() {
        guard let last = formatting.last, !last.isMarker, stackIndex(of: last.node) == nil else { return }
        var index = formatting.count - 1
        while index > 0 {
            let previous = formatting[index - 1]
            if previous.isMarker || stackIndex(of: previous.node) != nil { break }
            index -= 1
        }
        while index < formatting.count {
            let entry = formatting[index]
            let node = insertForeignElement(tokenIndex: entry.tokenIndex, space: .html)
            formatting[index] = FormattingEntry(node: node, tokenIndex: entry.tokenIndex)
            index += 1
        }
    }

    // MARK: The adoption agency algorithm (13.2.6.4.7)

    /// For the end tag `name` of a formatting element (or the start tags that misnest one). The loop counts are the standard's: 8 and 3.
    mutating func adoptionAgency(_ subject: HTMLName, token: BuilderToken) {
        if isHTML(currentNode, subject), formattingIndex(of: currentNode) == nil {
            pop()
            return
        }
        var outer = 0
        while outer < 8 {
            outer += 1
            var found: Int?
            var scan = formatting.count - 1
            while scan >= 0, !formatting[scan].isMarker {
                if isHTML(formatting[scan].node, subject) {
                    found = scan
                    break
                }
                scan -= 1
            }
            guard let formattingPosition = found else {
                anyOtherEndTag(token)
                return
            }
            let entry = formatting[formattingPosition]
            let formattingElement = entry.node
            guard let formattingStackIndex = stackIndex(of: formattingElement) else {
                formatting.remove(at: formattingPosition)
                return
            }
            guard hasInScope(formattingElement) else { return }
            var furthest: Int?
            var scanStack = formattingStackIndex + 1
            while scanStack < stack.count {
                if isSpecial(stack[scanStack]) {
                    furthest = scanStack
                    break
                }
                scanStack += 1
            }
            guard let furthestIndex = furthest else {
                while stack.count > formattingStackIndex { pop() }
                formatting.remove(at: formattingPosition)
                return
            }
            adoptFurthestBlock(
                entry: entry,
                formattingElement: formattingElement,
                formattingStackIndex: formattingStackIndex,
                furthestIndex: furthestIndex,
                bookmark: formattingPosition
            )
        }
    }

    /// Steps 13 to 20 of the adoption agency algorithm: climb from the furthest block to the formatting element, giving each formatting element on the way a fresh copy, then move the furthest block's children under a copy of the formatting element.
    private mutating func adoptFurthestBlock(
        entry: FormattingEntry,
        formattingElement: Node,
        formattingStackIndex: Int,
        furthestIndex: Int,
        bookmark start: Int
    ) {
        let furthestBlock = stack[furthestIndex]
        let commonAncestor = stack[formattingStackIndex - 1]
        var bookmark = start
        var lastNode = furthestBlock
        var nodeIndex = furthestIndex
        var inner = 0
        while true {
            inner += 1
            nodeIndex -= 1
            var node = stack[nodeIndex]
            if node == formattingElement { break }
            if inner > 3, let position = formattingIndex(of: node) {
                formatting.remove(at: position)
                if position < bookmark { bookmark -= 1 }
            }
            guard let position = formattingIndex(of: node) else {
                stack.remove(at: nodeIndex)
                continue
            }
            let created = createElement(tokenIndex: formatting[position].tokenIndex, space: .html)
            formatting[position] = FormattingEntry(node: created, tokenIndex: formatting[position].tokenIndex)
            stack[nodeIndex] = created
            node = created
            if lastNode == furthestBlock { bookmark = position + 1 }
            document.append(lastNode, to: node)
            lastNode = node
        }
        let place = appropriatePlace(override: commonAncestor)
        document.detach(lastNode)
        insertNode(lastNode, at: place)
        let created = createElement(tokenIndex: entry.tokenIndex, space: .html)
        document.moveChildren(of: furthestBlock, to: created)
        document.append(created, to: furthestBlock)
        if let position = formattingIndex(of: formattingElement) {
            formatting.remove(at: position)
            if position < bookmark { bookmark -= 1 }
        }
        formatting.insert(
            FormattingEntry(node: created, tokenIndex: entry.tokenIndex),
            at: Swift.min(bookmark, formatting.count)
        )
        removeFromStack(formattingElement)
        if let below = stackIndex(of: furthestBlock) { stack.insert(created, at: below + 1) }
    }

    // MARK: Insertion mode

    /// 13.2.4.1: chooses the insertion mode from the stack.
    mutating func resetInsertionMode() {
        var index = stack.count - 1
        var last = false
        while index >= 0 {
            var node = stack[index]
            if index == 0 {
                last = true
                if !contextElement.isNone { node = contextElement }
            }
            if isHTMLElement(node) {
                switch name(of: node) {
                    case .td where !last, .th where !last:
                        mode = .inCell
                        return
                    case .tr:
                        mode = .inRow
                        return
                    case .tbody, .thead, .tfoot:
                        mode = .inTableBody
                        return
                    case .caption:
                        mode = .inCaption
                        return
                    case .colgroup:
                        mode = .inColumnGroup
                        return
                    case .table:
                        mode = .inTable
                        return
                    case .template:
                        mode = templateModes.last ?? .inTemplate
                        return
                    case .head where !last:
                        mode = .inHead
                        return
                    case .body:
                        mode = .inBody
                        return
                    case .frameset:
                        mode = .inFrameset
                        return
                    case .html:
                        mode = headPointer.isNone ? .beforeHead : .afterHead
                        return
                    default: break
                }
            }
            if last {
                mode = .inBody
                return
            }
            index -= 1
        }
        mode = .inBody
    }
}
