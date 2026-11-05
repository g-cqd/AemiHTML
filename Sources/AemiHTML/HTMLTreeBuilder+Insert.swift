internal import AemiKernel

extension HTMLTreeBuilder {
    struct Place {
        var parent: Node
        var before: Node
    }

    /// The contents fragment of a `template` element (its only child).
    func templateContents(of template: Node) -> Node { document.firstChild(template) }

    /// 13.2.6.1: the appropriate place for inserting a node, with foster parenting and templates.
    func appropriatePlace(override: Node = .none) -> Place {
        var parent = override.isNone ? currentNode : override
        var before = Node.none
        if fosterParenting, isHTML(parent, .table, .tbody, .tfoot, .thead, .tr) {
            let lastTemplate = stack.lastIndex { isHTML($0, .template) }
            let lastTable = stack.lastIndex { isHTML($0, .table) }
            let lastIndex: Int?
            switch (lastTemplate, lastTable) {
                case (nil, nil): lastIndex = nil
                case (let template?, nil): lastIndex = template
                case (nil, let table?): lastIndex = table
                case (let template?, let table?): lastIndex = Swift.max(template, table)
            }
            guard let index = lastIndex else { return Place(parent: stack.first ?? parent, before: .none) }
            let last = stack[index]
            if isHTML(last, .template) {
                parent = last
            } else if !document.parent(last).isNone {
                parent = document.parent(last)
                before = last
            } else {
                parent = index > 0 ? stack[index - 1] : parent
            }
        }
        if isHTML(parent, .template) { return Place(parent: templateContents(of: parent), before: .none) }
        return Place(parent: parent, before: before)
    }

    // MARK: Elements

    enum Adjust { case none, svg, mathml }

    /// 13.2.6.1: creates the element for the start tag at `tokenIndex` in `space`, with the attribute and name adjustments of foreign content.
    mutating func createElement(tokenIndex: Int, space: HTMLDocument.Namespace, adjust: Adjust = .none) -> Node {
        let nameSlot = tokenizer.out.tape[tokenIndex + 1]
        var nameRange = TapeSlot.make(tag: 0, aux: TapeSlot.aux(nameSlot), low: TapeSlot.low(nameSlot))
        var lower = tokenizer.out.bytes(range: nameRange)
        var atom = HTMLName.lookup(lower)
        if let replacement = nameOverride {
            nameOverride = nil
            atom = replacement.0
            nameRange = tokenizer.out.intern(replacement.1.utf8)
            lower = tokenizer.out.bytes(range: nameRange)
        }
        if adjust == .svg, let fixed = SVGAdjustments.tags[String(decoding: lower, as: UTF8.self)] {
            nameRange = tokenizer.out.intern(fixed.utf8)
        }
        let node = document.makeNode(.element, name: atom, space: space, nameRange: nameRange)
        let count = Int(TapeSlot.aux(tokenizer.out.tape[tokenIndex]) & 0xFFF)
        for number in 0 ..< count {
            let at = tokenIndex + 2 + number * 2
            let nameSlot = tokenizer.out.tape[at]
            let valueSlot = tokenizer.out.tape[at + 1]
            var name = TapeSlot.make(tag: 0, aux: TapeSlot.aux(nameSlot), low: TapeSlot.low(nameSlot))
            let value = TapeSlot.make(tag: 0, aux: TapeSlot.aux(valueSlot), low: TapeSlot.low(valueSlot))
            var namespace: UInt8 = 0
            if adjust != .none {
                let text = String(decoding: tokenizer.out.bytes(range: name), as: UTF8.self)
                if adjust == .svg, let fixed = SVGAdjustments.attributes[text] {
                    name = tokenizer.out.intern(fixed.utf8)
                } else if adjust == .mathml, text == "definitionurl" {
                    name = tokenizer.out.intern("definitionURL".utf8)
                }
                if let foreign = SVGAdjustments.foreign[text] {
                    name = tokenizer.out.intern(foreign.local.utf8)
                    namespace = foreign.namespace
                }
            }
            document.addAttribute(node, name: name, value: value, namespace: namespace)
        }
        if space == .html, atom == .template {
            let contents = document.makeNode(.templateContents)
            document.append(contents, to: node)
        }
        return node
    }

    /// Inserts `node` at the adjusted insertion location, unless that is a document that already has an element.
    mutating func insertNode(_ node: Node, at place: Place) {
        if place.parent == document.root {
            var child = document.firstChild(place.parent)
            while !child.isNone {
                if document.kind(child) == .element { return }
                child = document.nextSibling(child)
            }
        }
        document.insert(node, in: place.parent, before: place.before)
    }

    /// Creates an element for the start tag at `tokenIndex`, inserts it at the appropriate place and pushes it, unless the stack is already `maxDepth` deep (then it is a leaf: `lastInsertWasLeaf`).
    @discardableResult
    mutating func insertForeignElement(tokenIndex: Int, space: HTMLDocument.Namespace) -> Node {
        let adjust: Adjust = space == .svg ? .svg : (space == .mathml ? .mathml : .none)
        let node = createElement(tokenIndex: tokenIndex, space: space, adjust: adjust)
        let place = appropriatePlace()
        insertNode(node, at: place)
        if stack.count < maxDepth {
            push(node)
            lastInsertWasLeaf = false
        } else {
            lastInsertWasLeaf = true
        }
        if space == .mathml, document.names[Int(node.raw)] == HTMLName.annotationXml.rawValue,
            let encoding = tokenAttribute(BuilderToken(kind: .startTag, index: tokenIndex), "encoding")
        {
            let lowered = encoding.map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
            if lowered.elementsEqual("text/html".utf8) || lowered.elementsEqual("application/xhtml+xml".utf8) {
                htmlIntegrationAnnotations.insert(node.raw)
            }
        }
        return node
    }

    @discardableResult
    mutating func insertHTMLElement(_ token: BuilderToken) -> Node {
        insertForeignElement(tokenIndex: token.index, space: .html)
    }

    /// "Immediately pop the current node off the stack": the element just inserted, unless it was too deep to be pushed.
    mutating func popJustInserted() {
        if !lastInsertWasLeaf { pop() }
    }

    // MARK: Text, comments, processing instructions

    /// 13.2.6.1: inserts characters; the text joins the text node before the location when there is one.
    mutating func insertCharacters(_ range: UInt64, at override: Place? = nil) {
        let place = override ?? appropriatePlace()
        if place.parent == document.root { return }
        let previous = place.before.isNone ? document.lastChild(place.parent) : document.previousSibling(place.before)
        if !previous.isNone, document.kind(previous) == .text {
            appendText(range, to: previous)
        } else {
            let node = document.makeNode(.text, dataRange: range)
            document.insert(node, in: place.parent, before: place.before)
        }
    }

    /// Joins `range` to the data of a text node: by extending it when the two touch in the same buffer, else by copying both to the end of the scratch.
    mutating func appendText(_ range: UInt64, to node: Node) {
        let current = document.dataRanges[Int(node.raw)]
        let aux = Int(TapeSlot.aux(current))
        let new = Int(TapeSlot.aux(range))
        let (length, newLength) = (aux >> 1, new >> 1)
        if aux & 1 == new & 1, TapeSlot.low(current) + length == TapeSlot.low(range),
            length + newLength <= HTMLTokens.maxLength
        {
            document.dataRanges[Int(node.raw)] = TapeSlot.make(
                tag: 0,
                aux: UInt64((length + newLength) << 1 | (aux & 1)),
                low: TapeSlot.low(current)
            )
            return
        }
        let start = tokenizer.out.scratch.count
        // A scratch range at the end of the scratch that this node already owns is extended in place.
        if aux & 1 == 1, TapeSlot.low(current) + length == start, length + newLength <= HTMLTokens.maxLength {
            tokenizer.out.scratch.append(contentsOf: tokenizer.out.bytes(range: range))
            document.dataRanges[Int(node.raw)] = TapeSlot.make(
                tag: 0,
                aux: UInt64((length + newLength) << 1 | 1),
                low: TapeSlot.low(current)
            )
            return
        }
        let joined = Array(tokenizer.out.bytes(range: current)) + Array(tokenizer.out.bytes(range: range))
        document.dataRanges[Int(node.raw)] = tokenizer.out.intern(joined)
    }

    mutating func insertComment(_ range: UInt64, at place: Place? = nil) {
        let place = place ?? appropriatePlace()
        document.insert(document.makeNode(.comment, dataRange: range), in: place.parent, before: place.before)
    }

    mutating func insertProcessingInstruction(_ token: BuilderToken, at place: Place? = nil) {
        let place = place ?? appropriatePlace()
        let target = tokenizer.out.tape[token.index + 1]
        let data = tokenizer.out.tape[token.index + 2]
        let node = document.makeNode(
            .processingInstruction,
            nameRange: TapeSlot.make(tag: 0, aux: TapeSlot.aux(target), low: TapeSlot.low(target)),
            dataRange: TapeSlot.make(tag: 0, aux: TapeSlot.aux(data), low: TapeSlot.low(data))
        )
        document.insert(node, in: place.parent, before: place.before)
    }

    // MARK: Generic RCDATA and raw text parsing (13.2.6.2)

    mutating func parseRawText(_ token: BuilderToken, rcdata: Bool) {
        insertHTMLElement(token)
        tokenizer.switchTo(rcdata ? .rcdata : .rawtext)
        originalMode = mode
        mode = .text
    }
}
