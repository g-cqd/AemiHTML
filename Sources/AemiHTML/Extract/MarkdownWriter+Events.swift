extension MarkdownWriter {
    /// One step of the walk: text is written, elements open and close their structure. An element that is dropped, or that is written whole (code, a table), is skipped with its children.
    mutating func handle(_ event: HTMLDocument.WalkEvent, _ walker: inout HTMLDocument.Walker) {
        switch event {
            case .enter(let node):
                guard skipped.isNone else { return }
                switch document.kind(node) {
                    case .text: writeText(document.data(node))
                    case .element:
                        if document.isDropped(node, hidden: options.dropsHiddenContent) {
                            skipped = node
                            walker.skipChildren()
                        } else {
                            enter(node, &walker)
                        }
                    default: break
                }
            case .exit(let node):
                if !skipped.isNone {
                    if node == skipped { skipped = .none }
                    return
                }
                if document.kind(node) == .element { exit(node) }
        }
    }

    private func name(_ node: HTMLDocument.Node) -> HTMLName { HTMLName(rawValue: document.atom(node)) ?? .unknown }

    private mutating func enter(_ node: HTMLDocument.Node, _ walker: inout HTMLDocument.Walker) {
        let isHTML = document.namespace(node) == .html
        switch isHTML ? name(node) : .unknown {
            case .table:
                writeTable(node)
                walker.skipChildren()
            case .pre, .listing:
                writePre(node)
                walker.skipChildren()
            case .code, .kbd, .samp, .tt:
                writeInlineCode(node)
                walker.skipChildren()
            case .h1, .h2, .h3, .h4, .h5, .h6: startHeading(name(node))
            case .ul, .ol: startList(node)
            case .li: startItem(node)
            case .blockquote:
                blockBoundary()
                if markdown {
                    prefixes.append(Prefix(first: Array("> ".utf8), rest: Array("> ".utf8)))
                } else {
                    prefixes.append(Prefix(first: [], rest: []))
                }
            case .hr:
                blockBoundary()
                writeRaw("---".utf8)
                blockBoundary()
            case .br:
                if inline || headingDepth > 0 { pendingSpace = true } else { hardBreak() }
            case .img: writeImage(node)
            case .a: startLink(node)
            case .strong, .b: openMark("**", "**")
            case .em, .i, .cite, .dfn: openMark("*", "*")
            case .s, .strike, .del: openMark("~~", "~~")
            case .input: writeCheckbox(node)
            case .dt, .summary:
                blockBoundary()
                openMark("**", "**")
            default:
                if document.isBlock(node) { blockBoundary() }
        }
    }

    private mutating func exit(_ node: HTMLDocument.Node) {
        let isHTML = document.namespace(node) == .html
        switch isHTML ? name(node) : .unknown {
            case .h1, .h2, .h3, .h4, .h5, .h6:
                headingDepth = 0
                blockBoundary()
            case .ul, .ol:
                if !lists.isEmpty { lists.removeLast() }
                if lists.isEmpty { blockBoundary() } else { finishLine() }
            case .li:
                if let last = prefixes.last, last.used { finishLine() }
                if !prefixes.isEmpty { prefixes.removeLast() }
                needBlank = false
            case .blockquote:
                if !prefixes.isEmpty { prefixes.removeLast() }
                blockBoundary()
            case .a: closeLink()
            case .strong, .b, .em, .i, .cite, .dfn, .s, .strike, .del: closeMark()
            case .dt, .summary:
                closeMark()
                blockBoundary()
            default:
                if document.isBlock(node) { blockBoundary() }
        }
    }

    // MARK: Headings, lists, breaks

    private mutating func startHeading(_ name: HTMLName) {
        blockBoundary()
        headingDepth = 1
        guard markdown, !inline else { return }
        let level: Int
        switch name {
            case .h1: level = 1
            case .h2: level = 2
            case .h3: level = 3
            case .h4: level = 4
            case .h5: level = 5
            default: level = 6
        }
        beginLine()
        out.append(contentsOf: [UInt8](repeating: 0x23, count: level))
        out.append(0x20)
        lineHasContent = false
        // A heading's text starts after the hashes: it is not the start of a line, so a `#` in it need not be escaped, but nothing else changes.
    }

    private mutating func startList(_ node: HTMLDocument.Node) {
        let ordered = name(node) == .ol
        var start = 1
        if ordered, let value = document.attribute("start", of: node),
            let number = Int(String(decoding: value, as: UTF8.self))
        {
            start = number
        }
        if prefixes.last.map({ !$0.used }) ?? false || (!lists.isEmpty && lineHasContent) {
            finishLine()
        } else {
            blockBoundary()
        }
        lists.append(ListState(ordered: ordered, next: start))
    }

    private mutating func startItem(_ node: HTMLDocument.Node) {
        guard !inline else {
            pendingSpace = true
            return
        }
        finishLine()
        guard var list = lists.popLast() else {
            prefixes.append(
                markdown ? Prefix(first: Array("- ".utf8), rest: Array("  ".utf8)) : Prefix(first: [], rest: [])
            )
            return
        }
        let marker = markdown ? (list.ordered ? "\(list.next). " : "- ") : ""
        list.next += 1
        lists.append(list)
        prefixes.append(Prefix(first: Array(marker.utf8), rest: [UInt8](repeating: 0x20, count: marker.utf8.count)))
    }

    private mutating func hardBreak() {
        guard !atLineStart else { return }
        flushMarks()
        if markdown { out.append(0x5C) }
        finishLine()
    }

    private mutating func writeCheckbox(_ node: HTMLDocument.Node) {
        guard !prefixes.isEmpty, let type = document.attribute("type", of: node),
            type.map(HTMLBuilderRules.lower).elementsEqual("checkbox".utf8)
        else { return }
        writeRaw((document.attribute("checked", of: node) != nil ? "[x] " : "[ ] ").utf8)
        lineHasContent = false
    }

    // MARK: Links and images

    private mutating func startLink(_ node: HTMLDocument.Node) {
        guard markdown, let href = document.attribute("href", of: node) else { return }
        var destination = String(decoding: href, as: UTF8.self)
        if let resolver = options.linkResolver {
            guard let resolved = resolver(destination) else { return }
            destination = resolved
        }
        guard HTMLDocument.isSafeDestination(destination) else { return }
        marks.append(Mark(opener: [0x5B], closer: Array("](\(Self.destination(destination)))".utf8)))
        linkMarks.append(marks.count)
    }

    private mutating func closeLink() {
        guard let depth = linkMarks.last, depth == marks.count else { return }
        linkMarks.removeLast()
        closeMark()
    }

    /// A link destination as Markdown writes it: bare, or in angle brackets when it holds a space or an unbalanced parenthesis.
    static func destination(_ text: String) -> String {
        let trimmed = text.trimmingSpaces()
        var open = 0
        var balanced = true
        for scalar in trimmed.unicodeScalars {
            if scalar == "(" { open += 1 }
            if scalar == ")" {
                if open == 0 { balanced = false } else { open -= 1 }
            }
        }
        if balanced, open == 0, !trimmed.contains(" "), !trimmed.contains("<"), !trimmed.contains(">") {
            return trimmed
        }
        let escaped = trimmed.replacingScalars(["<": "\\<", ">": "\\>", "\n": "%0A"])
        return "<" + escaped + ">"
    }

    private mutating func writeImage(_ node: HTMLDocument.Node) {
        let alt = document.attribute("alt", of: node).map { String(decoding: $0, as: UTF8.self) } ?? ""
        let altText = alt.collapsingWhitespace()
        switch options.images {
            case .drop: return
            case .altText:
                if !altText.isEmpty { writeText(ArraySlice(altText.utf8)) }
            case .markdown:
                guard markdown, let source = document.attribute("src", of: node) else {
                    if !altText.isEmpty { writeText(ArraySlice(altText.utf8)) }
                    return
                }
                let destination = String(decoding: source, as: UTF8.self)
                guard !destination.lowercased().hasPrefix("data:"), HTMLDocument.isSafeDestination(destination) else {
                    if !altText.isEmpty { writeText(ArraySlice(altText.utf8)) }
                    return
                }
                flushMarks()
                beginLine()
                if pendingSpace, lineHasContent { out.append(0x20) }
                pendingSpace = false
                out.append(contentsOf: Array("![".utf8))
                for byte in altText.utf8 where byte != 0x0A { writeAltByte(byte) }
                out.append(contentsOf: Array("](\(Self.destination(destination)))".utf8))
                lineHasContent = true
        }
    }

    private mutating func writeAltByte(_ byte: UInt8) {
        if byte == 0x5B || byte == 0x5D || byte == 0x5C { out.append(0x5C) }
        out.append(byte)
    }
}

extension String {
    func collapsingWhitespace() -> String {
        var result = ""
        var pending = false
        for character in self {
            if character == " " || character == "\n" || character == "\t" || character == "\r" || character == "\u{0C}"
            {
                pending = !result.isEmpty
            } else {
                if pending { result.append(" ") }
                pending = false
                result.append(character)
            }
        }
        return result
    }

    func trimmingSpaces() -> String {
        var scalars = Substring(self)
        while let first = scalars.first, first == " " || first == "\n" || first == "\t" { scalars.removeFirst() }
        while let last = scalars.last, last == " " || last == "\n" || last == "\t" { scalars.removeLast() }
        return String(scalars)
    }

    func replacingScalars(_ map: [Character: String]) -> String {
        var result = ""
        for character in self { result += map[character] ?? String(character) }
        return result
    }
}
